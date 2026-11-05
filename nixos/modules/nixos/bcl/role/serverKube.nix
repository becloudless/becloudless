{ inputs, config, lib, pkgs, ... }:
let
  cfg = config.bcl.role.serverKube;
  nodeIp = n: lib.bcl.net.ipAdd cfg.firstNodeIp (n - 1);
  nodeName = n: "${config.bcl.role.serverKube.clusterName}${toString n}";
  nodeNumber = lib.strings.toInt(builtins.substring ((builtins.stringLength config.networking.hostName) -1)  (-1) config.networking.hostName);
  myIp = nodeIp nodeNumber;
  kubeadmStaticConfigPath = "/etc/kubernetes/kubeadm.yaml";
  # Copy of the static config with the etcd state decided at boot (the static one is read-only).
  kubeadmInitConfigPath = "/run/kubeadm/kubeadm.yaml";
  etcdJoinExistingCluster = pkgs.writeShellApplication {
    name = "etcd-join-existing-cluster";
    runtimeInputs = [ pkgs.etcd pkgs.kubernetes pkgs.gawk pkgs.gnused pkgs.coreutils ];
    text = lib.bcl.kube.etcdJoinExistingClusterScript {
      memberName = nodeName nodeNumber;
      peerUrl = "https://${myIp}:2380";
      otherMasterEndpoints = map (n: "https://${nodeIp n}:2379")
        (lib.filter (n: n != nodeNumber) (lib.range 1 cfg.masterNodeCount));
      staticConfigPath = kubeadmStaticConfigPath;
      initConfigPath = kubeadmInitConfigPath;
    };
  };
in
{
  options.bcl.role.serverKube = {
    clusterName = lib.mkOption {type = lib.types.str;};
    firstNodeIp = lib.mkOption {
      type = lib.types.str;
      default = lib.bcl.net.cidrhost config.bcl.network.cidr 1;
      defaultText = lib.literalExpression "first address of `bcl.network.cidr`";
      description = "IP address of the first master node (node 1). Other master node IPs are computed by adding their node index minus one to this address.";
    };
    masterNodeCount = lib.mkOption {
      type = lib.types.int;
      default = 1;
      description = "Number of master nodes in the cluster";
    };
    worker = lib.mkOption {
      type = lib.types.bool;
      readOnly = true;
      default = nodeNumber > cfg.masterNodeCount;
      defaultText = lib.literalExpression "node number of the host name > masterNodeCount";
      description = ''
        Whether this node is a worker only (kubelet + cri-o + a local haproxy to the apiservers, no etcd nor control-plane components):
        the nodes after the `masterNodeCount` first ones (the node number is the last digits of the hostname).
      '';
    };
  };

  ####################

  config = lib.mkMerge [
    { bcl.role.knownRoles = [ "serverKube" ]; }
    (lib.mkIf (config.bcl.role.name == "serverKube") {

    bcl.role.autoUpgrade.useHostNumber = lib.mkDefault true; # the nodes upgrade on different days

    bcl.role.setAdminPassword = true; # being able to log in to console
    security.sudo.wheelNeedsPassword = false;

    bcl.network.bridge = true; # we need a bridge for kube

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
      inputs.fim.packages.${pkgs.stdenv.hostPlatform.system}.fim
    ];

    programs.bash.interactiveShellInit = lib.mkIf (config.users.users.root.shell == pkgs.bash) ''
      export KUBECONFIG=/etc/kubernetes/admin.conf
      alias k='kubectl'
    '';

    services.resolved.settings.Resolve.DNSSEC = "true";
    networking.firewall.enable = false;

    systemd.network.networks.kube = {
      matchConfig = {
        Name = "kube* veth* cilium* lxc*";
      };
      linkConfig = {
        Unmanaged = true;
      };
    };

    services.openiscsi.enable = true;
    services.openiscsi.name = "iqn.2016-04.com.open-iscsi:543a6fbe2d4c"; # dummy name taken from archlinux

    #
    systemd.services."kubeadm" = lib.mkIf (!cfg.worker) {
      serviceConfig = {
        Type = "oneshot";
        RuntimeDirectory = "kubeadm";
        # A failed join must be retried, never silently replaced by a new cluster.
        Restart = "on-failure";
        RestartSec = 30;
      };

      preStart = "${etcdJoinExistingCluster}/bin/etcd-join-existing-cluster";

      script = ''
        ${pkgs.kubernetes}/bin/kubeadm init --skip-phases=preflight,bootstrap-token,addon/coredns,addon/kube-proxy,show-join-command --config=${kubeadmInitConfigPath}
      '';
      after = [ "network-online.target" "time-sync.target" ];
      wants = [ "network-online.target" "time-sync.target" ];
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
        EnvironmentFile = lib.mkIf (!cfg.worker) "/var/lib/kubelet/kubeadm-flags.env";
        ExecStart = lib.mkIf (!cfg.worker) "${pkgs.kubernetes}/bin/kubelet --config=/var/lib/kubelet/config.yaml --kubeconfig=/etc/kubernetes/kubelet.conf $KUBELET_KUBEADM_ARGS";
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
      127.0.0.1       kube.${config.bcl.global.domain}

      ${nodeIp 1}   ${nodeName 1}
      ${nodeIp 2}   ${nodeName 2}
      ${nodeIp 3}   ${nodeName 3}
      ${nodeIp 4}   ${nodeName 4}
      ${nodeIp 5}   ${nodeName 5}
      ${nodeIp 6}   ${nodeName 6}
      ${nodeIp 7}   ${nodeName 7}
    '';

    environment.etc."crictl.yaml".text = ''
      runtime-endpoint: "unix:///var/run/crio/crio.sock"
      image-endpoint: "unix:///var/run/crio/crio.sock"
    '';

    # systemctl stop kubeadm kubelet
    # crictl ps -q | xargs crictl stop
    # rm -Rf /var/lib/kubelet/* /var/lib/etcd/* /etc/kubernetes/pki/{apiserver*,front-proxy-client.*,etcd/server.*,etcd/peer.*,etcd/healthcheck-client.*} /etc/kubernetes/{admin.conf,controller-manager.conf,kubelet.conf,super-admin.conf,scheduler.conf,manifests/kube-*}
    # rm -Rf /var/lib/kubelet/* /var/lib/etcd/* /etc/kubernetes/pki/* /etc/kubernetes/{admin.conf,controller-manager.conf,kubelet.conf,super-admin.conf,scheduler.conf,manifests/kube-*}
    environment.etc."kubernetes/kubeadm.yaml".enable = !cfg.worker;
    environment.etc."kubernetes/kubeadm.yaml".text = ''
        apiVersion: kubelet.config.k8s.io/v1beta1
        kind: KubeletConfiguration
        cgroupDriver: systemd
        failSwapOn: false
        maxPods: 200
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
            - "${myIp}"
            peerCertSANs:
            - "${myIp}"
            extraArgs:
              initial-cluster: ${lib.concatMapStringsSep "," (n: "${nodeName n}=https://${nodeIp n}:2380") (lib.genList (n: n + 1) cfg.masterNodeCount)}
              initial-cluster-state: new
              name: ${nodeName nodeNumber}
              listen-peer-urls: https://${myIp}:2380
              listen-client-urls: https://${myIp}:2379
              advertise-client-urls: https://${myIp}:2379
              initial-advertise-peer-urls: https://${myIp}:2380
        apiServer:
          extraArgs:
            advertise-address: ${myIp}
            etcd-servers: ${lib.concatMapStringsSep "," (n: "https://${nodeIp n}:2379") (lib.genList (n: n + 1) cfg.masterNodeCount)}
            feature-gates: "SidecarContainers=true"
          certSANs:
          - kube.${config.bcl.global.domain} # service name
          - kube.${cfg.clusterName}.i.${config.bcl.global.domain} # service name
          - ${nodeIp 1}
          - ${nodeIp 2}
          - ${nodeIp 3}
          - ${nodeIp 4}
          - ${nodeIp 5}
          - ${nodeIp 6}
          - ${nodeIp 7}
          - ${nodeName 1}
          - ${nodeName 2}
          - ${nodeName 3}
          - ${nodeName 4}
          - ${nodeName 5}
          - ${nodeName 6}
          - ${nodeName 7}
          - 127.0.0.1
          - 127.0.0.2
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
          advertiseAddress: "${myIp}"
        nodeRegistration:
          criSocket: unix:///var/run/crio/crio.sock
          taints: []
      '';


    environment.persistence."/nix" = {
      hideMounts = true;
      directories = [
        { directory = "/var/lib/kubelet"; mode = "u=rwx,g=,o="; }
        { directory = "/var/lib/longhorn"; mode = "u=rwx,g=,o="; }
      ] ++ lib.optional (!cfg.worker) { directory = "/var/lib/etcd"; mode = "u=rwx,g=,o="; };
    };
  })
  ];
}
