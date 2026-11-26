{ config, lib, pkgs, ... }:
let
  cfg = config.bcl.role.kube;
  nodeIp = n: lib.bcl.net.ipAdd cfg.firstNodeIp (n - 1);

  # The node number is the last digit of the host name (`kube.nix`), the name of a node is its host name: the cluster name is not part of it.
  nodeNumber = lib.strings.toInt (builtins.substring ((builtins.stringLength config.networking.hostName) - 1) (-1) config.networking.hostName);
  hostPrefix = lib.removeSuffix (toString nodeNumber) config.networking.hostName;

  # Same range as the hosts of `kube.nix`: the highest node number of a cluster.
  maxNodeNumber = 7;

  # The nodes that are not masters any more, the highest number first: a node that is down has to go before the ones that are up, etcd
  # refuses to remove a member while the started members would not be a majority of the remaining ones (`unhealthy cluster`).
  staleNodes = lib.reverseList (lib.range (cfg.masterNodeCount + 1) maxNodeNumber);

  # Removes from etcd the members of the nodes that are not masters any more, and the control-plane labels of these nodes. The members are
  # found by their peer URL (the address of a node number above `masterNodeCount`), not by their name: a cluster renamed in the past has
  # members with an older name. Nothing else is touched. etcd refuses to remove a member when it would lose its quorum (strict reconfig
  # check), the service is retried until it goes through.
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

      # Columns of the member list: id, status, name, peer urls, client urls, learner.
      memberIdOfPeer() {
        etcdctlOnMasters member list | awk -F', ' -v peer="$1" 'index($4, peer) { print $1; exit }'
      }

      # The removal of the next members depends on this one: stop at the first one that can not go through, the service is retried.
      prune() {
        node=$1
        peer=$2
        memberId=$(memberIdOfPeer "$peer")
        [ -n "$memberId" ] || return 0
        echo "Removing the etcd member of $node ($peer, $memberId): the node is not a master any more"
        if ! etcdctlOnMasters member remove "$memberId"; then
          # another master may have removed it at the same time
          [ -z "$(memberIdOfPeer "$peer")" ] || return 1
        fi
      }

      ${lib.concatMapStringsSep "\n" (n: ''prune "${hostPrefix}${toString n}" "https://${nodeIp n}:2380"'') staleNodes}

      # kubeadm marks the masters with these labels, the kubelet of a node that became a worker does not remove them
      export KUBECONFIG=/etc/kubernetes/admin.conf
      ${lib.concatMapStringsSep "\n" (n: ''kubectl label node "${hostPrefix}${toString n}" node-role.kubernetes.io/control-plane- node.kubernetes.io/exclude-from-external-load-balancers- 2>/dev/null || true'') staleNodes}
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
