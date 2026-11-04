{ inputs, config, lib, pkgs, ... }:
let
  cfg = config.bcl.role.serverKube;
  nodeIp = n: lib.bcl.net.ipAdd cfg.firstNodeIp (n - 1);
  nodeName = n: "${config.bcl.role.serverKube.clusterName}${toString n}";
  nodeNumber = lib.strings.toInt(builtins.substring ((builtins.stringLength config.networking.hostName) -1)  (-1) config.networking.hostName);
  myIp = nodeIp nodeNumber;

  # Set on the node by `kube-drain` when it cordons it, so the node is uncordoned at the next boot (and only then: a node cordoned by hand stays so).
  uncordonAnnotation = "becloudless.net/uncordon-on-boot";

  # Masters have the cluster admin kubeconfig. Workers hold the cluster CA (see serverKubeWorker.nix), so they sign a short-lived admin client
  # certificate: their own node identity is not allowed to evict pods nor to cordon.
  kubeLib = ''
    setup_kubeconfig() {
      ${if cfg.worker then ''
      umask 077
      mkdir -p /run/kube-drain
      kubeadm kubeconfig user --client-name kube-drain --org system:masters --validity-period 1h \
        --config /etc/kubernetes/kubeadm-worker.yaml > /run/kube-drain/kubeconfig.new
      mv /run/kube-drain/kubeconfig.new /run/kube-drain/kubeconfig
      export KUBECONFIG=/run/kube-drain/kubeconfig
      '' else ''
      export KUBECONFIG=/etc/kubernetes/admin.conf
      ''}
    }
  '';

  # Drains the node, respecting the PodDisruptionBudgets: the eviction is retried until the budgets allow it, or the timeout is reached.
  kubeDrain = pkgs.writeShellApplication {
    name = "kube-drain";
    runtimeInputs = [ pkgs.kubernetes pkgs.coreutils ];
    text = ''
      ${kubeLib}
      setup_kubeconfig
      node=${config.networking.hostName}
      if [ "$(kubectl get node "$node" -o jsonpath='{.spec.unschedulable}')" != true ]; then
        kubectl annotate node "$node" ${uncordonAnnotation}=true --overwrite
      fi
      timeout ${toString (cfg.shutdownDrainTimeout + 30)} kubectl drain "$node" --timeout ${toString cfg.shutdownDrainTimeout}s --ignore-daemonsets --delete-emptydir-data
    '';
  };

  # At boot, uncordon the node if it was cordoned by `kube-drain`.
  kubeUncordonOnBoot = pkgs.writeShellApplication {
    name = "kube-uncordon-on-boot";
    runtimeInputs = [ pkgs.kubernetes pkgs.coreutils ];
    text = ''
      ${kubeLib}
      node=${config.networking.hostName}
      for _ in $(seq 120); do
        if setup_kubeconfig && value=$(kubectl get node "$node" -o jsonpath='{.metadata.annotations.becloudless\.net/uncordon-on-boot}' 2>/dev/null); then
          if [ "$value" = true ]; then
            kubectl uncordon "$node" && kubectl annotate node "$node" ${uncordonAnnotation}-
          fi
          break
        fi
        sleep 5
      done
    '';
  };

  # Runs under a logind delay inhibitor lock (see the `kube-drain` service): waits for the system to be asked to shut down, then drains
  # the node. logind only goes on with the shutdown once this exits (or after `InhibitDelayMaxSec`), so everything is still up.
  kubeDrainOnShutdown = pkgs.writeShellApplication {
    name = "kube-drain-on-shutdown";
    runtimeInputs = [ pkgs.systemd pkgs.coreutils ];
    text = ''
      until [ "$(busctl get-property org.freedesktop.login1 /org/freedesktop/login1 org.freedesktop.login1.Manager PreparingForShutdown)" = "b true" ]; do
        sleep 1
      done
      ${kubeDrain}/bin/kube-drain || echo "kube-drain failed or timed out, shutting down anyway"
    '';
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
      default = false;
      description = ''
        Run this node as a worker only (kubelet + cri-o + a local haproxy to the apiservers), without etcd nor control-plane
        components. The node number (last digits of the hostname) must be greater than `masterNodeCount`.
      '';
    };
    shutdownDrainTimeout = lib.mkOption {
      type = lib.types.ints.positive;
      default = 300;
      description = ''
        Maximum time in seconds the node waits, when the system is rebooted or powered off (`systemctl reboot`, power button, ...), for
        its pods to be evicted while respecting the PodDisruptionBudgets. Once over, the shutdown goes on without waiting any longer.
      '';
    };
  };

  ####################

  config = lib.mkMerge [
    { bcl.role.knownRoles = [ "serverKube" ]; }
    (lib.mkIf (config.bcl.role.name == "serverKube") {

    bcl.role.autoUpgrade.useHostNumber = lib.mkDefault true; # the nodes upgrade on different days

    assertions = [
      {
        assertion = cfg.worker -> nodeNumber > cfg.masterNodeCount;
        message = "bcl.role.serverKube.worker: node number ${toString nodeNumber} of ${config.networking.hostName} must be greater than masterNodeCount (${toString cfg.masterNodeCount}).";
      }
    ];

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

    users.users.root.packages = with pkgs; [
      kubeDrain
    ];

    programs.bash.interactiveShellInit = lib.mkIf (config.users.users.root.shell == pkgs.bash) ''
      export KUBECONFIG=/etc/kubernetes/admin.conf
      alias k='kubectl'
    '';

    services.resolved.settings.Resolve.DNSSEC = "true";
    networking.firewall.enable = false;

    # Drain the node, respecting the PodDisruptionBudgets, whatever triggers the reboot/poweroff through logind (`systemctl reboot`, power
    # button, ...). It cannot be done in the ExecStop of a service: the containers run in systemd scopes that are stopped as soon as the
    # shutdown starts, so the apiserver proxy is already gone by then. Instead the service holds a logind delay inhibitor lock: logind only
    # starts the shutdown once the drain is over, with the whole system still running.
    # Do not use the kubelet graceful node shutdown (`shutdownGracePeriod`) next to it: the kubelet would kill the pods as soon as logind
    # announces the shutdown, before the drain.
    services.logind.settings.Login.InhibitDelayMaxSec = cfg.shutdownDrainTimeout + 60;

    systemd.services."kube-drain" = {
      description = "Drain the kubernetes node before a shutdown";
      after = [ "network-online.target" "crio.service" "kubelet.service" ] ++ lib.optional cfg.worker "haproxy-apiserver.service";
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];
      restartIfChanged = false; # a deployment must not drain the node
      stopIfChanged = false;
      serviceConfig = {
        Type = "simple";
        ExecStart = "${pkgs.systemd}/bin/systemd-inhibit --what=shutdown --mode=delay --who=kube-drain --why=\"Draining the kubernetes node\" ${kubeDrainOnShutdown}/bin/kube-drain-on-shutdown";
      };
    };

    systemd.services."kube-uncordon-on-boot" = {
      description = "Uncordon the kubernetes node if it was cordoned by kube-drain";
      after = [ "network-online.target" "crio.service" "kubelet.service" ] ++ lib.optional cfg.worker "haproxy-apiserver.service";
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];
      restartIfChanged = false;
      stopIfChanged = false;
      serviceConfig = {
        Type = "simple";
        ExecStart = "${kubeUncordonOnBoot}/bin/kube-uncordon-on-boot";
      };
    };

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
      };

      preStart = ''
        # Check if this node needs to be added to an existing etcd cluster
        ETCD_DIR="/var/lib/etcd"
        MY_IP="${myIp}"
        MY_NAME="${nodeName nodeNumber}"
        FIRST_NODE_IP="${nodeIp 1}"

        # If etcd data doesn't exist and this is not the first node, check if we need to join an existing cluster
        if [ ! -d "$ETCD_DIR/member" ] && [ "${toString nodeNumber}" != "1" ]; then
          echo "No local etcd data found, checking first node for existing cluster..."

          # Check if first node has a running etcd cluster
          if ${pkgs.etcd}/bin/etcdctl --endpoints=https://$FIRST_NODE_IP:2379 \
            --cacert=/etc/kubernetes/pki/etcd/ca.crt \
            --cert=/etc/kubernetes/pki/etcd/peer.crt \
            --key=/etc/kubernetes/pki/etcd/peer.key \
            endpoint health >/dev/null 2>&1; then

            echo "Found existing etcd cluster on first node"

            # Check if this member is already in the cluster
            MEMBER_EXISTS=$(${pkgs.etcd}/bin/etcdctl --endpoints=https://$FIRST_NODE_IP:2379 \
              --cacert=/etc/kubernetes/pki/etcd/ca.crt \
              --cert=/etc/kubernetes/pki/etcd/peer.crt \
              --key=/etc/kubernetes/pki/etcd/peer.key \
              member list | grep "$MY_NAME" || echo "")

            if [ -z "$MEMBER_EXISTS" ]; then
              # Add as new member
              echo "Adding $MY_NAME to existing etcd cluster..."
              ${pkgs.etcd}/bin/etcdctl --endpoints=https://$FIRST_NODE_IP:2379 \
                --cacert=/etc/kubernetes/pki/etcd/ca.crt \
                --cert=/etc/kubernetes/pki/etcd/peer.crt \
                --key=/etc/kubernetes/pki/etcd/peer.key \
                member add $MY_NAME --peer-urls=https://$MY_IP:2380 || true

              # Update kubeadm config to use 'existing' state
              sed -i 's/initial-cluster-state: new/initial-cluster-state: existing/' /etc/kubernetes/kubeadm.yaml
              echo "Node added to existing cluster, will join with state=existing"
            else
              echo "Member already exists in cluster (likely recovering from data loss)"
              sed -i 's/initial-cluster-state: new/initial-cluster-state: existing/' /etc/kubernetes/kubeadm.yaml
            fi
          else
            echo "First node not available or no existing cluster found"
          fi
        else
          echo "Etcd data exists or this is the first node, proceeding with standard initialization"
        fi
      '';

      script = ''
        # bootstrap at very first node, first boot, with: kubeadm init --skip-phases=preflight --config=/etc/kubernetes/kubeadm.yaml
        ${pkgs.kubernetes}/bin/kubeadm init --skip-phases=preflight,bootstrap-token,addon/coredns,show-join-command --config=/etc/kubernetes/kubeadm.yaml
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
