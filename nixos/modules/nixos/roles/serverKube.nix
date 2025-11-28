{ config, lib, pkgs, ... }:
let
  srvNumber = lib.strings.toInt(builtins.substring ((builtins.stringLength config.networking.hostName) -1)  (-1) config.networking.hostName);
  clusterNumber = "1"; # TODO derive from config or hostname
  cfg = config.bcl.role.server;
in
{
  options.bcl.role.serverKube = {
    clusterName = lib.mkOption {type = lib.types.str;};
#    cidr = lib.mkOption {
#      type = lib.types.str;
#      default = "192.168.41.20/22";
#    };
    secretFile = lib.mkOption { type = lib.types.path;};
  };

  ####################

  config = lib.mkIf (config.bcl.role.name == "serverKube") {

    bcl.disk.encrypted = true;
    bcl.boot.ssh = true; # give password for disk encryption on boot

    bcl.role.setAdminPassword = true; # being able to log in to console
    security.sudo.wheelNeedsPassword = false;

    environment.systemPackages = with pkgs; [
      kubernetes
      cni-plugins
      cri-tools
      openiscsi nfs-utils
      ipset ipvsadm
      k9s
      etcd
      ssh-to-age
      mergerfs
    ];

    users.users.root.packages = with pkgs; [
      (writeShellScriptBin "kube-reboot" ''
        kubectl --kubeconfig=/etc/kubernetes/admin.conf drain ${config.networking.hostName} --timeout 200s --ignore-daemonsets --delete-emptydir-data || true
        systemctl reboot
      '')
      (writeShellScriptBin "kube-poweroff" ''
        kubectl --kubeconfig=/etc/kubernetes/admin.conf drain ${config.networking.hostName} --timeout 200s --ignore-daemonsets --delete-emptydir-data || true
        systemctl poweroff
      '')
    ];

    networking.nameservers = ["192.168.40.12"];
    services.resolved.dnssec = "true";
    networking.firewall.enable = false;

    systemd.network.enable = true;
    systemd.network.networks.net = {
      matchConfig = {
        Name = "en* eth*";
      };
      networkConfig = {
        IgnoreCarrierLoss = true;
        Bridge = "br0";
      };
    };
    systemd.network.netdevs.br0.netdevConfig = {
      Kind = "bridge";
      Name = "br0";
    };
    systemd.network.networks.br0 = {
      matchConfig = {
        Name = "br0";
      };
      networkConfig = {
        IgnoreCarrierLoss = true;
        KeepConfiguration = true;
      };
      address = [
        "192.168.41.${toString clusterNumber}${toString srvNumber}/22"
      ];
      routes = [
        {
          Gateway = "192.168.40.10";
          GatewayOnLink = true;
        }
      ];
    };

    systemd.network.networks.kube = {
      matchConfig = {
        Name = "kube* veth* cilium* lxc*";
      };
      linkConfig = {
        Unmanaged = true;
      };
    };

    services.openssh.ports = [ 22 (lib.strings.toInt "655${toString clusterNumber}${toString srvNumber}") ];
    services.openiscsi.enable = true;
    services.openiscsi.name = "iqn.2016-04.com.open-iscsi:543a6fbe2d4c"; # dummy name taken from archlinux

    #
    systemd.services."kubeadm" = {
      serviceConfig = {
        Type = "oneshot";
      };

      script = ''
        # bootstrap at very first node, first boot, with: kubeadm init --skip-phases=preflight --config=/etc/kubernetes/kubeadm.yaml
        ${pkgs.kubernetes}/bin/kubeadm init --skip-phases=preflight,bootstrap-token,addon/coredns,show-join-command --config=/etc/kubernetes/kubeadm.yaml
      '';
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];
    };

    systemd.sockets."cni-dhcp" = {
      unitConfig = {
        PartOf="cni-dhcp.service";
      };
      socketConfig = {
        ListenStream = "/run/cni/dhcp.sock";
        SocketUser = "root";
        SocketGroup = "root";
        SocketMode = "0600";
        RemoveOnStop = true;
      };
      wantedBy = [ "sockets.target" ];
    };

    systemd.services."cni-dhcp" = {
      serviceConfig = {
        ExecStart = "${pkgs.cni-plugins}/bin/dhcp daemon";
      };

      after = [ "network.target" "cni-dhcp.socket" ];
      requires = [ "cni-dhcp.socket" ];
      wantedBy = [ "multi-user.target" ];
    };


    # https://github.com/NixOS/nixpkgs/blob/master/nixos/modules/services/cluster/kubernetes/kubelet.nix
    systemd.services."kubelet" = {
      path = with pkgs; [
        gitMinimal
        openssh
        util-linux
        iproute2
        ethtool
        thin-provisioning-tools
        iptables
        socat
      ];
      preStart = ''
        ${lib.concatMapStrings (package: ''
          echo "Linking cni package: ${package}"
          mkdir -p /opt/cni/bin
          cp ${package}/bin/* /opt/cni/bin/
        '') [pkgs.cni-plugins]}
      '';
      serviceConfig = {
        ConfigurationDirectory = "kubernetes";
        CPUAccounting = true;
        IPAccounting = true;
        EnvironmentFile = "/var/lib/kubelet/kubeadm-flags.env";
        ExecStart = "${pkgs.kubernetes}/bin/kubelet --config=/var/lib/kubelet/config.yaml --kubeconfig=/etc/kubernetes/kubelet.conf $KUBELET_KUBEADM_ARGS";
        KillMode = "process";
        MemoryAccounting = true;
        Restart = "on-failure";
        RestartSec = 10;
        RuntimeDirectory = "kubelet";
        StateDirectory = "kubelet";
      };
    };

    boot.kernelModules = [ "overlay" "br_netfilter" "bridge" ];


    boot.kernel.sysctl = {
      "net.ipv4.ip_forward" = 1;
      "net.bridge.bridge-nf-call-ip6tables" = 1;
      "net.bridge.bridge-nf-call-iptables" = 1;
    };

    networking.extraHosts = ''
      127.0.0.1       srv${toString clusterNumber}${toString srvNumber}.h.${config.bcl.global.domain} ${config.networking.hostName} localhost
      127.0.0.1       kube.${config.bcl.global.domain}

      192.168.41.${toString clusterNumber}1   srv${toString clusterNumber}1
      192.168.41.${toString clusterNumber}2   srv${toString clusterNumber}2
      192.168.41.${toString clusterNumber}3   srv${toString clusterNumber}3
      192.168.41.${toString clusterNumber}4   srv${toString clusterNumber}4
      192.168.41.${toString clusterNumber}5   srv${toString clusterNumber}5
      192.168.41.${toString clusterNumber}6   srv${toString clusterNumber}6
      192.168.41.${toString clusterNumber}7   srv${toString clusterNumber}7
    '';

    environment.etc."crictl.yaml".text = ''
      runtime-endpoint: "unix:///var/run/crio/crio.sock"
      image-endpoint: "unix:///var/run/crio/crio.sock"
    '';

    # systemctl stop kubeadm kubelet
    # crictl ps -q | xargs crictl stop
    # rm -Rf /var/lib/kubelet/* /var/lib/etcd/* /etc/kubernetes/pki/{apiserver*,front-proxy-client.*,etcd/server.*,etcd/peer.*,etcd/healthcheck-client.*} /etc/kubernetes/{admin.conf,controller-manager.conf,kubelet.conf,super-admin.conf,scheduler.conf,manifests/kube-*}
    # rm -Rf /var/lib/kubelet/* /var/lib/etcd/* /etc/kubernetes/pki/* /etc/kubernetes/{admin.conf,controller-manager.conf,kubelet.conf,super-admin.conf,scheduler.conf,manifests/kube-*}
    environment.etc."kubernetes/kubeadm.yaml".text = ''
        apiVersion: kubelet.config.k8s.io/v1beta1
        kind: KubeletConfiguration
        cgroupDriver: systemd
        evictionHard:
          imagefs.available: 1%
          memory.available: 100Mi
          nodefs.available: 1%
          nodefs.inodesFree: 1%
        volumeStatsAggPeriod: "0"
        imageGCHighThresholdPercent: 99
        imageGCLowThresholdPercent: 97
        allowedUnsafeSysctls:
        - net.core.rmem_max
        featureGates:
          SidecarContainers: true
        ---
        apiVersion: kubeadm.k8s.io/v1beta3
        kind: ClusterConfiguration
        kubernetesVersion: stable
        #clusterName: cluster
        controlPlaneEndpoint: kube.${config.bcl.global.domain}:8443
        networking:
          serviceSubnet: 172.16.42.0/24
          podSubnet: 10.42.0.0/16
        etcd:
          local:
            serverCertSANs:
            - "192.168.41.${toString clusterNumber}${toString srvNumber}"
            peerCertSANs:
            - "192.168.41.${toString clusterNumber}${toString srvNumber}"
            extraArgs:
              initial-cluster: srv${toString clusterNumber}1=https://192.168.41.${toString clusterNumber}1:2380
              # TODO ,srv${toString clusterNumber}2=https://192.168.41.${toString clusterNumber}2:2380,srv${toString clusterNumber}5=https://192.168.41.${toString clusterNumber}5:2380,srv${toString clusterNumber}6=https://192.168.41.${toString clusterNumber}6:2380,srv${toString clusterNumber}7=https://192.168.41.${toString clusterNumber}7:2380
              initial-cluster-state: new
              name: srv${toString clusterNumber}${toString srvNumber}
              listen-peer-urls: https://192.168.41.${toString clusterNumber}${toString srvNumber}:2380
              listen-client-urls: https://192.168.41.${toString clusterNumber}${toString srvNumber}:2379
              advertise-client-urls: https://192.168.41.${toString clusterNumber}${toString srvNumber}:2379
              initial-advertise-peer-urls: https://192.168.41.${toString clusterNumber}${toString srvNumber}:2380
        apiServer:
          extraArgs:
            advertise-address: 192.168.41.${toString clusterNumber}${toString srvNumber}
            feature-gates: "SidecarContainers=true"
          certSANs:
          - kube.${config.bcl.global.domain} # service name
          - kube.${clusterName}.i.${config.bcl.global.domain} # service name
          - 192.168.41.${toString clusterNumber}1
          - 192.168.41.${toString clusterNumber}2
          - 192.168.41.${toString clusterNumber}3
          - 192.168.41.${toString clusterNumber}4
          - 192.168.41.${toString clusterNumber}5
          - 192.168.41.${toString clusterNumber}6
          - 192.168.41.${toString clusterNumber}7
          - 127.0.0.1
        controllerManager:
          extraArgs:
            bind-address: 0.0.0.0
            feature-gates: "SidecarContainers=true"
        scheduler:
          extraArgs:
            bind-address: 0.0.0.0
            feature-gates: "SidecarContainers=true"

        ---
        apiVersion: kubeadm.k8s.io/v1beta3
        kind: InitConfiguration
        localAPIEndpoint:
          advertiseAddress: "192.168.41.${toString clusterNumber}${toString srvNumber}"
        nodeRegistration:
          criSocket: unix:///var/run/crio/crio.sock
          taints: []
      '';


    environment.persistence."/nix" = {
      hideMounts = true;
      directories = [
        { directory = "/var/lib/kubelet"; mode = "u=rwx,g=,o="; }
        { directory = "/var/lib/longhorn"; mode = "u=rwx,g=,o="; }
        { directory = "/var/lib/etcd"; mode = "u=rwx,g=,o="; }
      ];
    };
  };
}
