{ lib, ... }:
let
  # Defines `etcdctlOnOtherMasters`, the etcdctl run against the other masters with the client certificate of kubeadm.
  etcdctlOnOtherMastersFunction = otherMasterEndpoints: ''
    etcdctlOnOtherMasters() {
      etcdctl --endpoints=${lib.concatStringsSep "," otherMasterEndpoints} --command-timeout=10s \
        --cacert=/etc/kubernetes/pki/etcd/ca.crt \
        --cert=/etc/kubernetes/pki/etcd/healthcheck-client.crt \
        --key=/etc/kubernetes/pki/etcd/healthcheck-client.key "$@"
    }
  '';
in
{
  kube = {
    kubeadmStaticConfigPath = "/etc/kubernetes/kubeadm.yaml";
    # Copy of the static config with the etcd state decided at boot (the static one is read-only).
    kubeadmInitConfigPath = "/run/kubeadm/kubeadm.yaml";

    # POSIX sh (also run by busybox in the kubelet container image), expects etcdctl, kubeadm, awk, sed and sleep in PATH.
    # Writes `initConfigPath`: `staticConfigPath` with `initial-cluster-state` set to `existing` and `initial-cluster` set to the
    # members of the running cluster when this node was (re)added to it, left as is otherwise.
    #
    # `joinAsLearner`: the node is added as a learner, which does not count for the quorum: the running cluster stays healthy
    # while the node starts (a voting member that is not started yet breaks the quorum of a small cluster, 1 to 2 members). The
    # learner has to be promoted once its etcd is in sync, see `etcdPromoteLearnerScript`.
    etcdJoinExistingClusterScript =
      { memberName
      , peerUrl
      , otherMasterEndpoints
      , staticConfigPath
      , initConfigPath
      , etcdDataDirectory ? "/var/lib/etcd"
      , joinAsLearner ? false
      }: ''
        initialClusterState=new
        initialCluster=""

        ${lib.optionalString (otherMasterEndpoints != [ ]) ''
          ${etcdctlOnOtherMastersFunction otherMasterEndpoints}
          # Written when this node is added to the running cluster, before its etcd creates its data: when the script runs again
          # in between (restart of the service) the running cluster may not be healthy yet, this node must not start a new one.
          addedMarker="${etcdDataDirectory}/added-to-existing-cluster"

          if [ -d "${etcdDataDirectory}/member" ]; then
            echo "etcd data found, nothing to join"
            rm -f "$addedMarker"
          else
            # Only the etcd CA exists on a fresh install: a client cert is needed to query the cluster.
            kubeadm init phase certs etcd-healthcheck-client --config ${staticConfigPath}

            # Healthy means quorum: while a brand new cluster is still forming nothing is healthy.
            otherMastersHealthy=false
            attempt=0
            while [ "$attempt" -lt 12 ]; do
              healthReport=$(etcdctlOnOtherMasters endpoint health 2>&1 || true)
              case "$healthReport" in
                *' is healthy'*)
                  otherMastersHealthy=true
                  break
                  ;;
              esac
              attempt=$((attempt + 1))
              sleep 5
            done

            if [ "$otherMastersHealthy" = true ]; then
              memberList=$(etcdctlOnOtherMasters member list)
              # Column 4 is the peer url, an unstarted member has no name yet.
              myMember=$(printf '%s\n' "$memberList" | awk -F', ' -v peerUrl="${peerUrl}" '$4 == peerUrl')
              myMemberId=$(printf '%s\n' "$myMember" | awk -F', ' '{print $1}')
              myMemberStatus=$(printf '%s\n' "$myMember" | awk -F', ' '{print $2}')

              # A started member with no local data is the previous install, it must be re-added.
              if [ -n "$myMember" ] && [ "$myMemberStatus" != unstarted ]; then
                echo "Removing stale etcd member $myMemberId"
                etcdctlOnOtherMasters member remove "$myMemberId"
                myMember=""
              fi
              if [ -z "$myMember" ]; then
                echo "Adding ${memberName} to the running etcd cluster"
                etcdctlOnOtherMasters member add ${memberName} --peer-urls="${peerUrl}" ${lib.optionalString joinAsLearner "--learner"}
              fi

              # The members of the initial cluster of an existing cluster have to be exactly the ones of the running cluster
              # (plus this node), not the ones of the final topology.
              memberList=$(etcdctlOnOtherMasters member list)
              initialCluster=$(printf '%s\n' "$memberList" | awk -F', ' -v memberName="${memberName}" -v peerUrl="${peerUrl}" '{
                name = $3
                if ($4 == peerUrl) name = memberName
                printf "%s%s=%s", separator, name, $4
                separator = ","
              }')
              mkdir -p "${etcdDataDirectory}"
              printf '%s' "$initialCluster" > "$addedMarker"
              initialClusterState=existing
            elif [ -f "$addedMarker" ]; then
              echo "The running etcd cluster is not healthy, but ${memberName} was already added to it: joining it"
              initialCluster=$(cat "$addedMarker")
              initialClusterState=existing
            else
              echo "No running etcd cluster found, bootstrapping a new one"
            fi
          fi
        ''}
        sed "s/initial-cluster-state: new/initial-cluster-state: $initialClusterState/" ${staticConfigPath} > ${initConfigPath}
        if [ -n "$initialCluster" ]; then
          sed -i "s|initial-cluster: .*|initial-cluster: $initialCluster|" ${initConfigPath}
        fi
      '';

    # Promotes this node when it is a learner of the running cluster (added by `etcdJoinExistingClusterScript` with
    # `joinAsLearner`), once its etcd is in sync with the leader. Exits when it is not a learner (anymore), and fails when it
    # is still one after an hour. Expects etcdctl, awk, sed and sleep in PATH.
    etcdPromoteLearnerScript =
      { peerUrl
      , otherMasterEndpoints
      }: ''
        ${etcdctlOnOtherMastersFunction otherMasterEndpoints}

        attempt=0
        while [ "$attempt" -lt 360 ]; do
          # Fails while the other masters are not reachable, or have no quorum.
          memberList=$(etcdctlOnOtherMasters member list 2>/dev/null || true)
          if [ -n "$memberList" ]; then
            # Column 4 is the peer url, column 6 tells if the member is a learner.
            myMember=$(printf '%s\n' "$memberList" | awk -F', ' -v peerUrl="${peerUrl}" '$4 == peerUrl')
            myMemberId=$(printf '%s\n' "$myMember" | awk -F', ' '{print $1}')
            myMemberIsLearner=$(printf '%s\n' "$myMember" | awk -F', ' '{print $6}')
            if [ "$myMemberIsLearner" != true ]; then
              echo "etcd member is not a learner, nothing to promote"
              exit 0
            fi
            # Refused until the learner is in sync with the leader.
            if etcdctlOnOtherMasters member promote "$myMemberId"; then
              echo "etcd learner $myMemberId promoted"
              exit 0
            fi
          fi
          attempt=$((attempt + 1))
          sleep 10
        done

        echo "etcd learner not promoted after an hour" >&2
        exit 1
      '';
  };
}
