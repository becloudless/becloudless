#!/usr/bin/env bash
# See the header of the values of the chart app-cnpg.
set -uo pipefail

MIN_AGE=${MIN_AGE:-1200}                 # seconds a primary has to be unready before its volumes are enlarged
STABLE_AGE=${STABLE_AGE:-600}            # seconds all the instances of a cluster have to be ready before a volume is shrunk
COOLDOWN=${COOLDOWN:-3600}               # seconds between two enlargements of the volumes of a cluster
MAX_SIZE_GI=${MAX_SIZE_GI:-20}           # a volume is never enlarged over this size
MAX_DATA_PERCENT=${MAX_DATA_PERCENT:-50} # the data of the databases has to fit in this part of the original size to shrink back
DRY_RUN=${DRY_RUN:-false}
NO_WAL_SPACE='no free disk space for WALs'
ENLARGED_AT='cnpg.bcl.tf/volume-repair-at'
OPT_OUT='cnpg.bcl.tf/volume-repair'

log() { echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) $*"; }

# 1Gi, 512Mi, 2Ti, 1073741824: the size in Mi
to_mi() {
  [[ $1 =~ ^[0-9]+(Ki|Mi|Gi|Ti)?$ ]] || return 1
  case $1 in
    *Ti) echo $(( ${1%Ti} * 1024 * 1024 ));;
    *Gi) echo $(( ${1%Gi} * 1024 ));;
    *Mi) echo "${1%Mi}";;
    *Ki) echo $(( ${1%Ki} / 1024 ));;
    *) echo $(( $1 / 1048576 ));;
  esac
}

event() { # namespace cluster reason message
  kubectl create -f - <<EOF || true
apiVersion: v1
kind: Event
metadata:
  generateName: volume-repair-
  namespace: $1
type: Warning
reason: $3
message: "$4"
involvedObject: {apiVersion: postgresql.cnpg.io/v1, kind: Cluster, name: $2, namespace: $1}
source: {component: volume-repair}
EOF
}

# A primary can not start when its volume has no free space for the WAL, the pod loops on `no free disk space for WALs` and the
# cluster is `Not enough disk space`. The volumes of the instances are enlarged.
enlarge() {
  local now candidates ns pod cluster age cluster_json pg_log archiving pvcs pending cur last name req cap at new add
  now=$(date +%s)
  candidates=$(kubectl get pods -A -l cnpg.io/podRole=instance -o json | jq -r --argjson now "$now" --argjson min "$MIN_AGE" '
    .items[]
    | select((.metadata.labels["cnpg.io/instanceRole"] // .metadata.labels.role) == "primary")
    | select(.metadata.deletionTimestamp == null)
    | ([.status.conditions[]? | select(.type == "Ready")][0]) as $ready
    | select($ready.status != "True")
    | ([.metadata.creationTimestamp, $ready.lastTransitionTime] | map(select(. != null) | fromdateiso8601) | max) as $since
    | select($now - $since >= $min)
    | [.metadata.namespace, .metadata.name, .metadata.labels["cnpg.io/cluster"], ($now - $since)] | @tsv') || return 1

  if [ -z "$candidates" ]; then
    log "no primary unready for more than ${MIN_AGE}s"
    return 0
  fi

  while IFS=$'\t' read -r ns pod cluster age; do
    local ctx="$ns/$pod (primary, unready for ${age}s)"
    cluster_json=$(kubectl -n "$ns" get clusters.postgresql.cnpg.io "$cluster" -o json) || { log "$ctx: cluster $cluster not found"; continue; }
    if [ "$(jq -r --arg k "$OPT_OUT" '.metadata.annotations[$k] // ""' <<<"$cluster_json")" = false ]; then
      log "$ctx: disabled by the annotation of the cluster"; continue
    fi
    if jq -e '.spec.walStorage != null' <<<"$cluster_json" >/dev/null; then
      log "$ctx: the cluster has a volume for the WAL, not handled"; continue
    fi
    # not piped to `grep -q`: it exits first, and pipefail fails
    pg_log=$(kubectl -n "$ns" logs "$pod" -c postgres --tail=3000 2>/dev/null)
    if ! grep -q "$NO_WAL_SPACE" <<<"$pg_log"; then
      log "$ctx: no full WAL volume in its log, not a reason to enlarge the volumes"; continue
    fi
    # the WAL is kept until it is archived: when the archive does not work, a bigger volume is only filled later
    archiving=$(jq -r '[.status.conditions[]? | select(.type == "ContinuousArchiving")][0].status // "True"' <<<"$cluster_json")
    if [ "$archiving" != True ]; then
      log "$ctx: the WAL archive does not work, a bigger volume would be filled again"; continue
    fi

    pvcs=$(kubectl -n "$ns" get pvc -l "cnpg.io/cluster=$cluster" -o json | jq -r --arg k "$ENLARGED_AT" '
      .items[] | [.metadata.name, .spec.resources.requests.storage, (.status.capacity.storage // .spec.resources.requests.storage), (.metadata.annotations[$k] // "0")] | @tsv') || continue
    [ -n "$pvcs" ] || { log "$ctx: no volume found"; continue; }
    pending=false cur=0 last=0
    while IFS=$'\t' read -r name req cap at; do
      req=$(to_mi "$req") && cap=$(to_mi "$cap") || { pending=unknown; break; }
      [ "$req" -gt "$cap" ] && pending=true
      [ "$req" -gt "$cur" ] && cur=$req
      [ "$at" -gt "$last" ] 2>/dev/null && last=$at
    done <<<"$pvcs"
    if [ "$pending" != false ]; then
      log "$ctx: a volume is being resized ($pending), waiting"; continue
    fi
    if [ $(( $(date +%s) - last )) -lt "$COOLDOWN" ]; then
      log "$ctx: the volumes were enlarged less than ${COOLDOWN}s ago, waiting"; continue
    fi
    if [ "$cur" -ge $(( MAX_SIZE_GI * 1024 )) ]; then
      log "$ctx: the volumes are already at the maximum size (${MAX_SIZE_GI}Gi), the cause has to be fixed"; continue
    fi
    add=$(( cur / 2 > 1024 ? cur / 2 : 1024 ))
    new=$(( (cur + add + 1023) / 1024 ))
    [ "$new" -gt "$MAX_SIZE_GI" ] && new=$MAX_SIZE_GI

    if [ "$DRY_RUN" = true ]; then
      log "$ctx: DRY RUN, would enlarge the volumes of $cluster from $((cur / 1024))Gi to ${new}Gi (its WAL volume is full)"; continue
    fi
    log "$ctx: enlarging the volumes of $cluster from $((cur / 1024))Gi to ${new}Gi (its WAL volume is full)"
    local failed=false
    for name in $(cut -f1 <<<"$pvcs"); do
      kubectl -n "$ns" patch pvc "$name" --type merge -p \
        "{\"metadata\":{\"annotations\":{\"$ENLARGED_AT\":\"$(date +%s)\"}},\"spec\":{\"resources\":{\"requests\":{\"storage\":\"${new}Gi\"}}}}" || failed=true
    done
    [ "$failed" = true ] && { log "$ctx: a volume could not be patched"; continue; }
    event "$ns" "$cluster" VolumeEnlarged "the volumes of $cluster were enlarged from $((cur / 1024))Gi to ${new}Gi: the WAL volume of $pod was full"
  done <<<"$candidates"
}

# The volumes enlarged above are brought back to the size of the cluster, one instance by run: the PVC and the pod of a replica are
# deleted, the operator clones it again at the size of the spec. The primary is first switched over to a replica, then it is a replica.
shrink() {
  local now clusters id ns cluster cluster_json spec pods count ready pvcs data_mi size_b primary name cap inst target stale_pvc stale_pod primary_big
  now=$(date +%s)
  clusters=$(kubectl get pvc -A -l cnpg.io/cluster -o json | jq -r --arg k "$ENLARGED_AT" '
    [.items[] | select(.metadata.annotations[$k] != null) | .metadata.namespace + "/" + .metadata.labels["cnpg.io/cluster"]] | unique[]') || return 1

  for id in $clusters; do
    ns=${id%%/*} cluster=${id#*/}
    cluster_json=$(kubectl -n "$ns" get clusters.postgresql.cnpg.io "$cluster" -o json) || { log "$id: cluster not found"; continue; }
    if [ "$(jq -r --arg k "$OPT_OUT" '.metadata.annotations[$k] // ""' <<<"$cluster_json")" = false ]; then
      log "$id: disabled by the annotation of the cluster"; continue
    fi
    if [ "$(jq -r '.status.phase // ""' <<<"$cluster_json")" != "Cluster in healthy state" ]; then
      log "$id: the cluster is not healthy, the volumes are not shrunk"; continue
    fi
    spec=$(to_mi "$(jq -r '.spec.storage.size // ""' <<<"$cluster_json")") || { log "$id: no storage size in the spec"; continue; }
    primary=$(jq -r '.status.currentPrimary // ""' <<<"$cluster_json")
    count=$(jq -r '.spec.instances' <<<"$cluster_json")

    pods=$(kubectl -n "$ns" get pods -l "cnpg.io/cluster=$cluster,cnpg.io/podRole=instance" -o json) || continue
    ready=$(jq -r --argjson now "$now" --argjson min "$STABLE_AGE" --argjson count "$count" '
      [.items[] | select(.metadata.deletionTimestamp == null)
       | ([.status.conditions[]? | select(.type == "Ready")][0]) as $r
       | select($r.status == "True" and ($now - ($r.lastTransitionTime | fromdateiso8601)) >= $min)] | length == $count' <<<"$pods")
    if [ "$ready" != true ]; then
      log "$id: not all the $count instances are ready for ${STABLE_AGE}s, the volumes are not shrunk"; continue
    fi

    pvcs=$(kubectl -n "$ns" get pvc -l "cnpg.io/cluster=$cluster" -o json | jq -r '
      .items[] | select(.metadata.deletionTimestamp == null) | [.metadata.name, (.status.capacity.storage // .spec.resources.requests.storage), .metadata.labels["cnpg.io/instanceName"]] | @tsv') || continue
    stale_pvc="" stale_pod="" primary_big=false
    while IFS=$'\t' read -r name cap inst; do
      cap=$(to_mi "$cap") || continue
      [ "$cap" -gt "$spec" ] || continue
      if [ "$inst" = "$primary" ]; then primary_big=true; elif [ -z "$stale_pvc" ]; then stale_pvc=$name stale_pod=$inst; fi
    done <<<"$pvcs"
    if [ -z "$stale_pvc" ] && [ "$primary_big" != true ]; then
      log "$id: no volume bigger than the ${spec}Mi of the spec"; continue
    fi

    # the new volume holds all the data (and the WAL starts empty)
    size_b=$(kubectl -n "$ns" exec "$primary" -c postgres -- psql -U postgres -tAc \
      "select coalesce(sum(pg_database_size(datname)), 0)::bigint from pg_database" 2>/dev/null | tr -d '[:space:]')
    if ! [[ $size_b =~ ^[0-9]+$ ]]; then
      log "$id: the size of the databases is unknown, the volumes are not shrunk"; continue
    fi
    data_mi=$(( size_b / 1048576 ))
    if [ $(( data_mi * 100 )) -gt $(( spec * MAX_DATA_PERCENT )) ]; then
      log "$id: the databases are ${data_mi}Mi, over ${MAX_DATA_PERCENT}% of the ${spec}Mi of the spec, the volumes are not shrunk"; continue
    fi

    if [ -n "$stale_pvc" ]; then
      if [ "$DRY_RUN" = true ]; then
        log "$id: DRY RUN, would clone $stale_pod again at ${spec}Mi (delete the PVC $stale_pvc and the pod)"; continue
      fi
      log "$id: cloning the replica $stale_pod again at ${spec}Mi from the primary $primary (delete the PVC $stale_pvc and the pod)"
      kubectl -n "$ns" delete pvc "$stale_pvc" --wait=false || continue
      kubectl -n "$ns" delete pod "$stale_pod" --wait=false || continue
      event "$ns" "$cluster" VolumeShrunk "$stale_pod was cloned again at ${spec}Mi from $primary: its volume was enlarged by volume-repair"
    else
      target=$(jq -r --arg p "$primary" '[.items[] | select(.metadata.name != $p) | .metadata.name] | sort | first // ""' <<<"$pods")
      if [ -z "$target" ]; then
        log "$id: the primary $primary is alone, its volume can not be shrunk"; continue
      fi
      if [ "$DRY_RUN" = true ]; then
        log "$id: DRY RUN, would switch over from $primary to $target, the old primary is cloned again at ${spec}Mi after"; continue
      fi
      log "$id: switching over from $primary to $target, the old primary is cloned again at ${spec}Mi after"
      kubectl -n "$ns" patch clusters.postgresql.cnpg.io "$cluster" --subresource=status --type merge -p \
        "{\"status\":{\"targetPrimary\":\"$target\",\"targetPrimaryTimestamp\":\"$(date -u +%Y-%m-%dT%H:%M:%S).000000Z\",\"phase\":\"Switchover in progress\",\"phaseReason\":\"Switching over to $target\"}}" || continue
      event "$ns" "$cluster" VolumeShrinkSwitchover "switching over from $primary to $target to shrink the volume of $primary, enlarged by volume-repair"
    fi
  done
}

enlarge || exit 1
shrink || exit 1
