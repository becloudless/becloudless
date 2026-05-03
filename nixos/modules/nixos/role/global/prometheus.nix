{ config, lib, pkgs, ... }:

{

  config = lib.mkIf (config.bcl.role.name != "") {

    systemd.services."prometheus-node-exporter-nixos" = {
      path = with pkgs; [ jq ];
      serviceConfig = {
         Type = "oneshot";
      };
      script = ''
        set -eu

        booted="$(readlink /run/booted-system/{initrd,kernel,kernel-modules})"
        built="$(readlink /nix/var/nix/profiles/system/{initrd,kernel,kernel-modules})"

        mkdir -p /var/run/node-exporter-textfile
        rebootNeeded=0
        if [ "$booted" != "$built" ]; then
          rebootNeeded=1
        fi
        echo "nixos_reboot_needed $rebootNeeded" > /run/node-exporter-textfile/reboot.prom
        echo "nixos_version{version=\"$(/run/current-system/sw/bin/nixos-version --json | jq -r .nixosVersion)\"} 1" > /run/node-exporter-textfile/version.prom
      '';
    };

    systemd.timers."prometheus-node-exporter-nixos" = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "1m";
        OnUnitActiveSec = "1h";
        Unit = "prometheus-node-exporter-nixos.service";
      };

    };

    systemd.services."prometheus-pushprox-client" = {
      path = with pkgs; [ openssh coreutils gawk gnused ];
      script = ''
        username="pushprox-${config.bcl.group.name}"
        password="$(sed -e 's/[[:space:]]*$//' /nix/etc/ssh/ssh_host_ed25519_key | tr -d '\n' | sha256sum | awk '{print $1}')"
        domain="pushprox.${config.bcl.global.domain}"
        ${pkgs.bcl.prometheus-pushprox}/bin/pushprox-client --proxy-url="https://$username:$password@$domain" --log.level=warn
      '';

      after = [ "prometheus-node-exporter.service" ];
      requires = [ "prometheus-node-exporter.service" ];
      wantedBy = [ "multi-user.target" ];
    };

    services.prometheus.exporters.smartctl = {
      enable = true;
      listenAddress = "[::1]";
      devices = config.bcl.system.devices;
    };

    # https://nixos.org/manual/nixos/stable/#module-services-prometheus-exporters
    services.prometheus.exporters.node = {
      enable = true;
      port = 9100;
      # nixos declare host shortname on 127.0.0.2
      # prometheus scrape metrics through the proxy using the shortname
      listenAddress = "127.0.0.2";
      # https://github.com/NixOS/nixpkgs/blob/nixos-24.05/nixos/modules/services/monitoring/prometheus/exporters.nix
      enabledCollectors = [
        "systemd"
        "processes"
      ];
      # /nix/store/zgsw0yx18v10xa58psanfabmg95nl2bb-node_exporter-1.8.1/bin/node_exporter  --help
      extraFlags = [
        "--collector.textfile.directory=/run/node-exporter-textfile"
  #        "--collector.ethtool"
  #        "--collector.softirqs"
  #        "--collector.tcpstat"
  #        "--collector.wifi"
      ];
    };
  };

}