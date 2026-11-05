{ lib, ... }:
{
  kube = {
    # POSIX sh (also run by busybox in the kubelet container image), expects etcdctl, kubeadm, awk, sed and sleep in PATH.
    # Writes `initConfigPath`: `staticConfigPath` with `initial-cluster-state` set to `existing` when this node was
    # (re)added to a running etcd cluster, left as `new` otherwise.
    etcdJoinExistingClusterScript =
      { memberName
      , peerUrl
      , otherMasterEndpoints
      , staticConfigPath
      , initConfigPath
      , etcdDataDirectory ? "/var/lib/etcd"
      }: ''
        initialClusterState=new

        ${lib.optionalString (otherMasterEndpoints != [ ]) ''
          etcdctlOnOtherMasters() {
            etcdctl --endpoints=${lib.concatStringsSep "," otherMasterEndpoints} --command-timeout=10s \
              --cacert=/etc/kubernetes/pki/etcd/ca.crt \
              --cert=/etc/kubernetes/pki/etcd/healthcheck-client.crt \
              --key=/etc/kubernetes/pki/etcd/healthcheck-client.key "$@"
          }

          if [ -d "${etcdDataDirectory}/member" ]; then
            echo "etcd data found, nothing to join"
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
                etcdctlOnOtherMasters member add ${memberName} --peer-urls="${peerUrl}"
              fi
              initialClusterState=existing
            else
              echo "No running etcd cluster found, bootstrapping a new one"
            fi
          fi
        ''}
        sed "s/initial-cluster-state: new/initial-cluster-state: $initialClusterState/" ${staticConfigPath} > ${initConfigPath}
      '';
  };
}
