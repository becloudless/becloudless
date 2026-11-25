{ config, lib, pkgs, ... }:
let
  cfg = config.bcl.role.kube;
  nodeIp = n: lib.bcl.net.ipAdd cfg.firstNodeIp (n - 1);

  # Same range as the hosts of `kube.nix`: the highest node number of a cluster.
  maxNodeNumber = 7;

  # Removes from etcd the members of the nodes that are not masters any more, and the control-plane labels of these nodes. Only the
  # members named `<clusterName><number>` with a number above `masterNodeCount` are removed: nothing else is touched. etcd refuses
  # to remove a member when it would lose its quorum (strict reconfig check), the service is retried until it goes through.
  etcdPruneMembers = pkgs.writeShellApplication {
    name = "etcd-prune-members";
    runtimeInputs = [ pkgs.etcd pkgs.kubernetes pkgs.gawk pkgs.coreutils ];
    text = ''
      etcdctlOnMasters() {
        etcdctl --endpoints=${lib.concatMapStringsSep "," (n: "https://${nodeIp n}:2379") (lib.range 1 cfg.masterNodeCount)} \
          --command-timeout=10s \
          --cacert=/etc/kubernetes/pki/etcd/ca.crt \
          --cert=/etc/kubernetes/pki/etcd/healthcheck-client.crt \
          --key=/etc/kubernetes/pki/etcd/healthcheck-client.key "$@"
      }

      memberList=$(etcdctlOnMasters member list)

      # Columns of the member list: id, status, name, peer urls, client urls, learner. Highest node number first.
      staleMembers=$(printf '%s\n' "$memberList" | awk -F', ' -v prefix="${cfg.clusterName}" -v max=${toString cfg.masterNodeCount} '
        index($3, prefix) == 1 && substr($3, length(prefix) + 1) ~ /^[0-9]+$/ {
          number = substr($3, length(prefix) + 1) + 0
          if (number > max) print number, $1
        }' | sort -rn)

      failed=0
      while read -r number memberId; do
        [ -n "$memberId" ] || continue
        echo "Removing the etcd member ${cfg.clusterName}$number ($memberId): the node is not a master any more"
        if ! etcdctlOnMasters member remove "$memberId"; then
          # another master may have removed it at the same time
          if etcdctlOnMasters member list | awk -F', ' -v id="$memberId" '$1 == id { found = 1 } END { exit !found }'; then
            failed=1
          fi
        fi
      done <<< "$staleMembers"

      # kubeadm marks the masters with these labels, the kubelet of a node that became a worker does not remove them
      export KUBECONFIG=/etc/kubernetes/admin.conf
      for number in $(seq ${toString (cfg.masterNodeCount + 1)} ${toString maxNodeNumber}); do
        kubectl label node "${cfg.clusterName}$number" node-role.kubernetes.io/control-plane- node.kubernetes.io/exclude-from-external-load-balancers- 2>/dev/null || true
      done

      exit "$failed"
    '';
  };
in
{
  config = lib.mkMerge [
    # Masters: remove the etcd members of the nodes that are not masters any more.
    (lib.mkIf (config.bcl.role.name == "kube" && !cfg.worker) {
      systemd.services."etcd-prune-members" = {
        description = "Remove from etcd the members of the nodes that are not masters any more";
        after = [ "network-online.target" "kubeadm.service" ];
        wants = [ "network-online.target" ];
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true; # run again on a deployment that changes the script (masterNodeCount)
          # etcd is not up yet right after the boot, and the removal is refused while the cluster is not healthy
          Restart = "on-failure";
          RestartSec = 60;
          ExecStart = "${etcdPruneMembers}/bin/etcd-prune-members";
        };
      };
    })

    # Nodes that are not masters (any more): the etcd data of the previous life must not be found when the node becomes a master
    # again, it would start with the stale member it left. It is set aside, not deleted.
    (lib.mkIf (config.bcl.role.name == "kube" && cfg.worker) {
      systemd.services."etcd-retire" = {
        description = "Set aside the etcd data of a node that is not a master any more";
        path = [ pkgs.procps pkgs.coreutils ];
        after = [ "kubelet.service" ];
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          Restart = "on-failure";
          RestartSec = 30;
        };
        script = ''
          # /nix/var/lib/etcd is where /var/lib/etcd is persisted on a master (see kube.nix)
          if [ -d /nix/var/lib/etcd/member ]; then
            if pgrep -x etcd > /dev/null; then
              echo "etcd is still running, waiting for the kubelet to stop it"
              exit 1
            fi
            retired="/nix/var/lib/etcd.retired-$(date +%Y%m%d%H%M%S)"
            echo "Setting aside the etcd data in $retired"
            mv /nix/var/lib/etcd "$retired"
          fi
          rm -f /etc/kubernetes/manifests/{etcd,kube-apiserver,kube-controller-manager,kube-scheduler}.yaml
        '';
      };
    })
  ];
}
