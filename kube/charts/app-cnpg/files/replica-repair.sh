#!/usr/bin/env bash
# See the header of the values of the chart app-cnpg.
set -uo pipefail

MIN_AGE=${MIN_AGE:-1200} # seconds a replica has to be unready before it is cloned again
DRY_RUN=${DRY_RUN:-false}
LOST_WAL='has already been removed'
# pg_rewind of the instance manager, when the replica was a primary that wrote past the point where the new primary forked off
DIVERGED='could not find common ancestor of the source and target cluster'

log() { echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) $*"; }

now=$(date +%s)
repaired=" "
candidates=$(kubectl get pods -A -l cnpg.io/podRole=instance -o json | jq -r --argjson now "$now" --argjson min "$MIN_AGE" '
  .items[]
  | select((.metadata.labels["cnpg.io/instanceRole"] // .metadata.labels.role) == "replica")
  | select(.metadata.deletionTimestamp == null)
  | ([.status.conditions[]? | select(.type == "Ready")][0]) as $ready
  | select($ready.status != "True")
  | ([.metadata.creationTimestamp, $ready.lastTransitionTime] | map(select(. != null) | fromdateiso8601) | max) as $since
  | select($now - $since >= $min)
  | [.metadata.namespace, .metadata.name, .metadata.labels["cnpg.io/cluster"], ($now - $since)] | @tsv') || exit 1

if [ -z "$candidates" ]; then
  log "no replica unready for more than ${MIN_AGE}s"
  exit 0
fi

while IFS=$'\t' read -r ns pod cluster age; do
  id="$ns/$cluster"
  ctx="$ns/$pod (unready for ${age}s)"
  case "$repaired" in *" $id "*) log "$ctx: another instance of $id was cloned again by this run, next time"; continue;; esac

  cluster_json=$(kubectl -n "$ns" get clusters.postgresql.cnpg.io "$cluster" -o json) || { log "$ctx: cluster $cluster not found"; continue; }
  if [ "$(jq -r '.metadata.annotations["cnpg.bcl.tf/replica-repair"] // ""' <<<"$cluster_json")" = false ]; then
    log "$ctx: disabled by the annotation of the cluster"; continue
  fi
  primary=$(jq -r '.status.currentPrimary // ""' <<<"$cluster_json")
  if [ -z "$primary" ] || [ "$primary" = "$pod" ]; then
    log "$ctx: no other primary ($primary)"; continue
  fi
  primary_ready=$(kubectl -n "$ns" get pod "$primary" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)
  if [ "$primary_ready" != True ]; then
    log "$ctx: the primary $primary is not ready, nothing is deleted without a healthy copy"; continue
  fi

  # not piped to `grep -q`: it exits first, and pipefail fails
  pg_log=$(kubectl -n "$ns" logs "$pod" -c postgres --tail=3000 2>/dev/null)
  if grep -q "$DIVERGED" <<<"$pg_log"; then
    # the WAL archive does not help: the data of the replica is not a prefix of the history of the primary
    reason="its data diverged from the primary (pg_rewind finds no common ancestor of the timelines)"
  elif grep -q "$LOST_WAL" <<<"$pg_log"; then
    if jq -e '(.spec.backup.barmanObjectStore != null) or ([.spec.plugins[]? | select(.isWALArchiver == true)] | length > 0)' <<<"$cluster_json" >/dev/null; then
      log "$ctx: the cluster has a WAL archive, the replica can recover from it"; continue
    fi
    reason="the WAL it needs was removed from the primary"
  else
    log "$ctx: neither a lost WAL nor a diverged timeline in its log, not a reason to clone it again"; continue
  fi

  if [ "$DRY_RUN" = true ]; then
    log "$ctx: DRY RUN, would clone again from $primary (delete the PVCs and the pod): $reason"; continue
  fi
  log "$ctx: $reason, cloning it again from the primary $primary (delete the PVCs and the pod)"
  kubectl -n "$ns" delete pvc -l "cnpg.io/cluster=$cluster,cnpg.io/instanceName=$pod" --wait=false || continue
  kubectl -n "$ns" delete pod "$pod" --wait=false || continue
  repaired="$repaired$id "
  kubectl create -f - <<EOF || true
apiVersion: v1
kind: Event
metadata:
  generateName: replica-repair-
  namespace: $ns
type: Warning
reason: ReplicaRecloned
message: "$pod was cloned again from $primary: $reason (unready for ${age}s)"
involvedObject: {apiVersion: postgresql.cnpg.io/v1, kind: Cluster, name: $cluster, namespace: $ns}
source: {component: replica-repair}
EOF
done <<<"$candidates"
