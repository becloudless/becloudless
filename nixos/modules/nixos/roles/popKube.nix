{ inputs, config, lib, pkgs, ... }:

{
  config = lib.mkIf (config.bcl.role.name == "popKube") {
    bcl.disk.encrypted = true;
    bcl.boot.ssh = true;

    security.sudo.wheelNeedsPassword = false;
    systemd.network.enable = true;
    systemd.network.networks.net = {
      matchConfig = {
        Name = "en*";
      };
      networkConfig = {
        DHCP = "yes";
        IPv6AcceptRA = true;
      };
      linkConfig.RequiredForOnline = "routable";
    };

    environment.systemPackages = with pkgs; [
      k9s
    ];

    networking.firewall.enable = false;

    systemd.services."flux-bootstrap" = {
      path = with pkgs; [
        bash
        gitMinimal
        openssh
        openssl
        yq-go
        kubernetes-helm
        kubectl
        ssh-to-age
        sops
        gawk
      ];
      serviceConfig = {
        Type = "oneshot";
      };

      script = ''
        mkdir -p /root/.cache
        cd /root/.cache
        if [ ! -d infra ]; then
          git clone git@gitea.${config.bcl.global.domain}:${config.bcl.global.name}/infra.git
        else
          git -C infra pull
        fi
        cd infra/kube/pop
        sleep 30
        bash -x ../../bin/kube-bootstrap.sh
      '';
      after = [ "k3s.service" ];
      wants = [ "k3s.service" ];
      wantedBy = [ "multi-user.target" ];
    };

    systemd.services.k3s = {
      serviceConfig = {
        TimeoutStartUSec="10min";
        TimeoutStopUSec="10min";
        TimeoutSec="10min";
      };
    };

    services.k3s = {
      enable = true;
      extraFlags = [
        "--tls-san=${config.networking.hostName}.${config.bcl.global.domain},pop.${config.bcl.global.domain}"
      ];
    };

    environment.variables = {
      KUBECONFIG= "/etc/rancher/k3s/k3s.yaml";
    };

    boot.kernel.sysctl."vm.swappiness" = 10;
    swapDevices = [{
      device = "/nix/swapfile";
      size = 5 * 1024;
    }];

    environment.persistence."/nix" = {
      hideMounts = true;
      directories = [
        { directory = "/var/lib/kubelet"; mode = "u=rwx,g=,o="; }
        { directory = "/var/lib/rancher"; mode = "u=rwx,g=,o="; }
        { directory = "/etc/rancher"; mode = "u=rwx,g=,o="; }
      ];
    };


  };
}
