{ config, lib, pkgs, ... }:
let
  cfg = config.bcl.role.serverKube;
  nodeNumber = lib.strings.toInt (builtins.substring ((builtins.stringLength config.networking.hostName) - 1) (-1) config.networking.hostName);
  myIp = lib.bcl.net.ipAdd cfg.firstNodeIp (nodeNumber - 1);
in
{
  # etcd never gives freed space back to the filesystem: defragment the local member when the db is mostly free space.
  # A defrag blocks the member for a few seconds, so the timers are staggered (one member per hour).
  config = lib.mkIf (config.bcl.role.name == "serverKube" && !cfg.worker) {
    systemd.services."etcd-defrag" = {
      description = "Defragment the local etcd member when it is mostly free space";
      path = [ pkgs.etcd pkgs.jq ];
      environment = {
        ETCDCTL_API = "3";
        ETCDCTL_ENDPOINTS = "https://${myIp}:2379";
        ETCDCTL_CACERT = "/etc/kubernetes/pki/etcd/ca.crt";
        ETCDCTL_CERT = "/etc/kubernetes/pki/etcd/healthcheck-client.crt";
        ETCDCTL_KEY = "/etc/kubernetes/pki/etcd/healthcheck-client.key";
      };
      serviceConfig.Type = "oneshot";
      script = ''
        status=$(etcdctl endpoint status -w json)
        size=$(jq '.[0].Status.dbSize' <<<"$status")
        used=$(jq '.[0].Status.dbSizeInUse' <<<"$status")
        if [ "$size" -lt 104857600 ] || [ $((used * 100 / size)) -ge 50 ]; then
          echo "no defrag needed (size=$size inUse=$used)"
          exit 0
        fi
        echo "defragmenting (size=$size inUse=$used)"
        etcdctl defrag
      '';
    };

    systemd.timers."etcd-defrag" = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "*-*-* ${lib.fixedWidthNumber 2 nodeNumber}:30:00"; # node 1 at 01:30, node 2 at 02:30, ...
        Persistent = true;
      };
    };
  };
}
