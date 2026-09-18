{ config, lib, pkgs, ... }:
let
  cfg = config.bcl.role.server;
  kn = cfg.container.kubeletNode;
  controlPlaneHost = lib.head (lib.splitString ":" kn.controlPlaneEndpoint);

  # s6-overlay compiles its service database from /etc/s6-overlay/s6-rc.d at
  # container STARTUP (not image build time), so this extra oneshot service
  # can be added purely via bind-mounted files. cilium's cluster-wide
  # DaemonSet hardcodes --devices=br0/--direct-routing-device=br0, matching
  # masters' own VM NIC name ("br0") - Docker names this container's macvlan
  # interface "eth0" by convention, so rename it to match what cilium expects
  # before kubeadm/kubelet start.
  netrenameFiles = {
    "etc/s6-overlay/s6-rc.d/netrename/type" = "oneshot\n";
    "etc/s6-overlay/s6-rc.d/netrename/up" = ''
      /bin/sh -c "
        if ip link show eth0 >/dev/null 2>&1 && ! ip link show br0 >/dev/null 2>&1; then
          gw=$(ip route show default dev eth0 | awk '{print $3}')
          ip link set eth0 down
          ip link set eth0 name br0
          ip link set br0 up
          if [ -n \"$gw\" ]; then
            ip route add default via \"$gw\" dev br0
          fi
        fi
      "
    '';
    "etc/s6-overlay/s6-rc.d/netrename/dependencies.d/base" = "";
    "etc/s6-overlay/s6-rc.d/kubeadm/dependencies.d/netrename" = "";
  };

  # standard path is /usr/libexec/cni, but multus installs its binary into /opt/cni/bin
  cniBinDirsFile = {
    "etc/containerd/conf.d/cni-bin-dirs.toml" = ''
      [plugins.'io.containerd.cri.v1.runtime'.cni]
        bin_dirs = ['/usr/libexec/cni', '/opt/cni/bin']
    '';
  };

  capExtraOptions = [
    "--device=/dev/kmsg" # kubelet's OOM watcher needs this
    "--cap-add=NET_ADMIN" # cilium/kube-proxy manage iptables/routes/netns
    "--cap-add=NET_RAW" # cilium/kube-proxy use raw sockets (e.g. iptables, ping health checks)
    "--cap-add=SYS_ADMIN" # nested runc needs mount/unshare/pivot_root
    "--cap-add=SYS_RESOURCE" # cgroup/rlimit management
    "--cap-add=SYS_PTRACE" # nested runc/containerd needs to nsenter/ptrace into container processes
    "--cap-add=SYS_MODULE" # cilium's own pod spec requests this cap for its init containers (e.g. clean-cilium-state)
    "--cap-add=MKNOD" # container runtime creates device nodes for containers
    "--cap-add=AUDIT_WRITE" # many images/tools write to the kernel audit log on startup
    "--cap-add=SETFCAP" # nested runc sets file capabilities when building container rootfs
    "--cap-add=DAC_READ_SEARCH" # nested runc/containerd needs to open files by fd across mount namespaces (open_by_handle_at)
    "--cap-add=SYSLOG" # required to open /dev/kmsg (device access alone isn't enough)
    "--cap-add=SYS_NICE" # iscsid: raise process priority
    "--cap-add=IPC_LOCK" # iscsid: mlockall
    "--security-opt=seccomp=unconfined" # nested runc needs syscalls (unshare/mount/keyctl/clone) the default profile blocks
    "--security-opt=apparmor=unconfined" # avoid apparmor confinement conflicts with the nested container runtime
    "--security-opt=systempaths=unconfined" # docker masks/read-onlys parts of /proc,/sys by default; cilium-cni needs to write rp_filter et al under /proc/sys/net
  ];

  # `staticPodPath` must ONLY be set for control-plane nodes: it's what
  # makes the long-running kubelet (--config=this file, baked into the
  # image's kubelet s6 service) actually watch /etc/kubernetes/manifests for
  # static pods (etcd/apiserver/scheduler/controller-manager/haproxy) -
  # without it they're silently never started even though kubeadm writes
  # their manifests there.
  kubeletConfigYaml = { staticPodPath ? null }: ''
    apiVersion: kubelet.config.k8s.io/v1beta1
    kind: KubeletConfiguration
    authentication:
      anonymous:
        enabled: false
      webhook:
        cacheTTL: 0s
        enabled: true
      x509:
        clientCAFile: /etc/kubernetes/pki/ca.crt
    authorization:
      mode: Webhook
      webhook:
        cacheAuthorizedTTL: 0s
        cacheUnauthorizedTTL: 0s
    cgroupDriver: cgroupfs
    containerRuntimeEndpoint: unix:///run/containerd/containerd.sock
    failSwapOn: false
    ${lib.optionalString (staticPodPath != null) "staticPodPath: ${staticPodPath}"}
    maxPods: 200
    evictionHard:
      imagefs.available: 1%
      memory.available: 100Mi
      nodefs.available: 1%
      nodefs.inodesFree: 1%
    volumeStatsAggPeriod: "0"
    imageGCHighThresholdPercent: 99
    imageGCLowThresholdPercent: 97
    clusterDNS:
    ${lib.concatMapStringsSep "\n" (ns: "- ${ns}") kn.clusterDNS}
    clusterDomain: cluster.local
    featureGates:
      SidecarContainers: true
      UserNamespacesSupport: true
  '';

  etcdMasters = lib.filterAttrs (n: m: m.etcdMember) kn.masters;
  haproxyMasters = lib.filterAttrs (n: m: m.haproxyBackend) kn.masters;

  mkWorkerContainer = name: w: {
    image = kn.image;
    network = {
      bridge = kn.bridge;
      cidr = kn.cidr;
      address = w.address;
      gateway = kn.gateway;
    };
    files = netrenameFiles // cniBinDirsFile // {
      "etc/kubernetes/kubeadm-worker.yaml" = ''
        apiVersion: kubeadm.k8s.io/v1beta3
        kind: ClusterConfiguration
        controlPlaneEndpoint: ${kn.controlPlaneEndpoint}
      '';
      "etc/kubernetes/kubelet-config.yaml" = kubeletConfigYaml { };
    };
    volumes = [
      "${config.sops.secrets."${name}-ca_crt".path}:/etc/kubernetes/pki/ca.crt:ro"
      "${config.sops.secrets."${name}-ca_key".path}:/etc/kubernetes/pki/ca.key:ro"
      "${w.dataDir}/var-lib-containerd:/var/lib/containerd" # Overlayfs cannot be on overlayfs
      "${w.dataDir}/opt-cni-bin:/opt/cni/bin:rshared" # multus's install-multus-binary init container needs this to be a shared mount
      "/sys/fs/bpf:/sys/fs/bpf:rshared" # cilium-envoy's mount-bpf-fs init container needs this to be a shared mount
    ] ++ w.extraVolumes;
    extraOptions = capExtraOptions
      # so this node can resolve the controlPlaneEndpoint hostname to every
      # master's address, without relying on cluster DNS being up yet
      ++ (map (m: "--add-host=${controlPlaneHost}:${m.address}") (lib.attrValues kn.masters))
      ++ w.extraOptions;
  };

  mkControlPlaneContainer = name: cp: {
    image = kn.image;
    network = {
      bridge = kn.bridge;
      cidr = kn.cidr;
      address = cp.address;
      gateway = kn.gateway;
    };
    files = netrenameFiles // cniBinDirsFile // {
      # Bind-mounted read-only (like every other `files.` entry), but the
      # kubeadm/up override below needs to `sed` it (to flip
      # initial-cluster-state) - so it's placed under a different name here
      # and copied to a real, writable path inside the container's own
      # (ephemeral) rootfs first.
      "etc/kubernetes/kubeadm.yaml.template" = ''
        apiVersion: kubeadm.k8s.io/v1beta3
        kind: ClusterConfiguration
        kubernetesVersion: stable
        controlPlaneEndpoint: ${kn.controlPlaneEndpoint}
        networking:
          serviceSubnet: ${kn.serviceSubnet}
          podSubnet: ${kn.podSubnet}
        etcd:
          local:
            serverCertSANs:
            - "${cp.address}"
            peerCertSANs:
            - "${cp.address}"
            extraArgs:
              initial-cluster: ${lib.concatStringsSep "," (lib.mapAttrsToList (n: m: "${n}=https://${m.address}:2380") etcdMasters)}
              initial-cluster-state: new
              name: ${name}
              listen-peer-urls: https://${cp.address}:2380
              listen-client-urls: https://${cp.address}:2379
              advertise-client-urls: https://${cp.address}:2379
              initial-advertise-peer-urls: https://${cp.address}:2380
        apiServer:
          extraArgs:
            advertise-address: ${cp.address}
            etcd-servers: ${lib.concatStringsSep "," (lib.mapAttrsToList (n: m: "https://${m.address}:2379") etcdMasters)}
            feature-gates: "SidecarContainers=true"
          certSANs:
          - ${controlPlaneHost}
          ${lib.concatMapStringsSep "\n" (s: "  - ${s}") (
            (lib.mapAttrsToList (n: m: m.address) kn.masters)
            ++ (lib.attrNames kn.masters)
            ++ kn.extraCertSANs
            ++ [ "127.0.0.1" "127.0.0.2" ]
          )}
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
          advertiseAddress: "${cp.address}"
        nodeRegistration:
          criSocket: unix:///run/containerd/containerd.sock
          taints: []

        ---
        # `kubeadm-bootstrap` (baked into the image) invokes `kubeadm init`
        # with no `--patches` flag, so a separately bind-mounted
        # kubelet-config.yaml file is never actually read in this
        # kubeadm-init control-plane flow. A KubeletConfiguration document
        # in the SAME --config=kubeadm.yaml file IS a mechanism kubeadm
        # init natively merges in, so it's placed here instead.
        apiVersion: kubelet.config.k8s.io/v1beta1
        kind: KubeletConfiguration
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
        clusterDNS:
        ${lib.concatMapStringsSep "\n" (ns: "- ${ns}") kn.clusterDNS}
        featureGates:
          SidecarContainers: true
          UserNamespacesSupport: true
      '';

      # iscsid runs on the true host instead (services.openiscsi below),
      # since the container's own netns can never reach the kernel's iSCSI
      # netlink socket. Leaving an image-baked iscsid running here too
      # would be actively harmful: with a shared PID namespace,
      # go-iscsi-helper's "find the iscsid process" scan could
      # non-deterministically pick this one instead of the host's, hitting
      # the exact same ECONNREFUSED bug. Replaced with a permanent no-op so
      # s6 has something to keep "up" without it doing anything. See
      # /memories/repo/lmr3-pid-host-s6-overlay-incompatibility.md.
      "etc/s6-overlay/s6-rc.d/iscsid/run" = ''
        #!/bin/sh
        exec sleep infinity
      '';

      # Overrides the image-baked kubeadm/up (which just runs
      # kubeadm-bootstrap unconditionally) with the same etcd-join preStart
      # logic VM masters run before `kubeadm init`, adapted for a
      # container: the etcd peer cert (needed to auth to the existing
      # cluster) doesn't pre-exist on a genuinely fresh container/volume
      # like it would on a long-lived VM, so it's generated locally first
      # from the mounted etcd CA - kubeadm init's own certs phase later
      # reuses this same file rather than regenerating it.
      #
      # s6-rc's "up" file is parsed as a single execline command line, not
      # directly exec'd as a script - so it just invokes /bin/sh against a
      # real script file below, rather than trying to embed the whole
      # (quote-heavy) script inline as an execline argument.
      "etc/s6-overlay/s6-rc.d/kubeadm/up" = "/bin/sh /etc/kubernetes/kubeadm-init.sh\n";

      "etc/kubernetes/kubeadm-init.sh" = ''
        #!/bin/sh
        set -e

        cp /etc/kubernetes/kubeadm.yaml.template /etc/kubernetes/kubeadm.yaml

        kubeadm init phase certs etcd-peer --config=/etc/kubernetes/kubeadm.yaml

        ETCD_DIR="/var/lib/etcd"
        MY_IP="${cp.address}"
        MY_NAME="${name}"
        FIRST_NODE_IP="${(lib.head (lib.attrValues etcdMasters)).address}"

        if [ ! -d "$ETCD_DIR/member" ]; then
          echo "No local etcd data found, checking first node for existing cluster..."

          if etcdctl --endpoints=https://$FIRST_NODE_IP:2379 \
            --cacert=/etc/kubernetes/pki/etcd/ca.crt \
            --cert=/etc/kubernetes/pki/etcd/peer.crt \
            --key=/etc/kubernetes/pki/etcd/peer.key \
            endpoint health >/dev/null 2>&1; then

            echo "Found existing etcd cluster on first node"

            MEMBER_EXISTS=$(etcdctl --endpoints=https://$FIRST_NODE_IP:2379 \
              --cacert=/etc/kubernetes/pki/etcd/ca.crt \
              --cert=/etc/kubernetes/pki/etcd/peer.crt \
              --key=/etc/kubernetes/pki/etcd/peer.key \
              member list | grep "$MY_NAME" || echo "")

            if [ -z "$MEMBER_EXISTS" ]; then
              echo "Adding $MY_NAME to existing etcd cluster..."
              etcdctl --endpoints=https://$FIRST_NODE_IP:2379 \
                --cacert=/etc/kubernetes/pki/etcd/ca.crt \
                --cert=/etc/kubernetes/pki/etcd/peer.crt \
                --key=/etc/kubernetes/pki/etcd/peer.key \
                member add $MY_NAME --peer-urls=https://$MY_IP:2380 || true
              sed -i 's/initial-cluster-state: new/initial-cluster-state: existing/' /etc/kubernetes/kubeadm.yaml
            else
              echo "Member already exists in cluster (likely recovering from data loss)"
              sed -i 's/initial-cluster-state: new/initial-cluster-state: existing/' /etc/kubernetes/kubeadm.yaml
            fi
          else
            echo "First node not available or no existing cluster found"
          fi
        else
          echo "Etcd data exists, proceeding with standard initialization"
        fi

        exec /etc/s6-overlay/scripts/kubeadm-bootstrap
      '';

      "etc/kubernetes/kubelet-config.yaml" = kubeletConfigYaml { staticPodPath = "/etc/kubernetes/manifests"; };

      # Same static haproxy pod every VM master runs, load-balancing this
      # node's own local :8443 (what controlPlaneEndpoint resolves to)
      # across all masters' :6443. Uses IPs directly (not hostnames), since
      # this container has no /etc/hosts entries for them.
      "etc/kubernetes/manifests/haproxy-apiserver.yaml" = ''
        apiVersion: v1
        kind: Pod
        metadata:
          annotations:
            scheduler.alpha.kubernetes.io/critical-pod: ""
          labels:
            component: haproxy
            tier: control-plane
          name: haproxy
          namespace: kube-system
        spec:
          containers:
          - image: haproxy:2.6.6
            livenessProbe:
              failureThreshold: 8
              httpGet:
                host: 127.0.0.1
                path: /
                port: 1936
                scheme: HTTP
              initialDelaySeconds: 15
              timeoutSeconds: 15
            name: haproxy-apiserver
            resources:
              requests:
                cpu: 250m
            volumeMounts:
            - mountPath: /usr/local/etc/haproxy
              name: hap-config
              readOnly: true
          hostNetwork: true
          priorityClassName: system-cluster-critical
          volumes:
          - name: hap-config
            hostPath:
              path: /etc/haproxy
      '';

      "etc/haproxy/haproxy.cfg" = ''
        defaults
            maxconn 20000
            mode    tcp
            option  dontlognull
            timeout http-request 10s
            timeout queue        1m
            timeout connect      10s
            timeout client       86400s
            timeout server       86400s
            timeout tunnel       86400s

        listen stats-health
          mode http
          bind 127.0.0.1:1936
          monitor-uri /
          stats enable
          stats uri /stats

        frontend k8s-api
          bind :8443
          mode tcp
          default_backend k8s-api

        backend k8s-api
          option  httpchk GET /readyz HTTP/1.0
          option  log-health-checks
          http-check expect status 200
          mode tcp
          balance roundrobin
          default-server verify none check-ssl inter 10s downinter 5s rise 2 fall 2 slowstart 60s maxconn 5000 maxqueue 5000 weight 100
        ${lib.concatMapStringsSep "\n" (n: "  server ${n} ${haproxyMasters.${n}.address}:6443 check") (lib.attrNames haproxyMasters)}
      '';
    };
    volumes = [
      "${config.sops.secrets."${name}-ca_crt".path}:/etc/kubernetes/pki/ca.crt:ro"
      "${config.sops.secrets."${name}-ca_key".path}:/etc/kubernetes/pki/ca.key:ro"
      "${config.sops.secrets."${name}-sa_pub".path}:/etc/kubernetes/pki/sa.pub:ro"
      "${config.sops.secrets."${name}-sa_key".path}:/etc/kubernetes/pki/sa.key:ro"
      "${config.sops.secrets."${name}-front_proxy_ca_crt".path}:/etc/kubernetes/pki/front-proxy-ca.crt:ro"
      "${config.sops.secrets."${name}-front_proxy_ca_key".path}:/etc/kubernetes/pki/front-proxy-ca.key:ro"
      "${config.sops.secrets."${name}-etcd_ca_crt".path}:/etc/kubernetes/pki/etcd/ca.crt:ro"
      "${config.sops.secrets."${name}-etcd_ca_key".path}:/etc/kubernetes/pki/etcd/ca.key:ro"
      "${cp.dataDir}/etcd:/var/lib/etcd"
      "${cp.dataDir}/kubelet:/var/lib/kubelet:rshared"
      "${cp.dataDir}/containerd:/var/lib/containerd"
      "${cp.dataDir}/opt-cni-bin:/opt/cni/bin:rshared"
      "/sys/fs/bpf:/sys/fs/bpf:rshared"
      # Real host /dev instead of the container's own private tmpfs one -
      # required so the device node the host's iscsid/Longhorn mknods for
      # an attached volume (in ITS OWN mount namespace, now the host's) is
      # actually visible to kubelet/containerd inside this container. Only
      # affects path VISIBILITY, not access: Docker's device cgroup still
      # blocks actual I/O on any major:minor not explicitly granted.
      "/dev:/dev"
    ] ++ cp.extraVolumes;
    extraOptions = capExtraOptions ++ [
      "--add-host=${controlPlaneHost}:127.0.0.1" # this node's own local haproxy static pod, same pattern as every VM master
    ] ++ cp.extraOptions;
  };
in
{
  options.bcl.role.server.container.kubeletNode = {
    image = lib.mkOption {
      type = lib.types.str;
      default = "ghcr.io/becloudless/alpine-kubelet:1.260917.2020";
      description = "Container image to run for every kubelet node (worker or control-plane) defined here.";
    };
    bridge = lib.mkOption {
      type = lib.types.str;
      default = "br50";
      description = "Docker macvlan network bridge every kubelet node container attaches to.";
    };
    cidr = lib.mkOption {
      type = lib.types.str;
      default = "192.168.50.0/24";
      description = "CIDR subnet of `bridge`'s network.";
    };
    gateway = lib.mkOption {
      type = lib.types.str;
      default = lib.bcl.net.cidrhost kn.cidr (-2);
      defaultText = lib.literalExpression "last usable address of `cidr`";
      description = "Gateway for `cidr`.";
    };
    controlPlaneEndpoint = lib.mkOption {
      type = lib.types.str;
      example = "kube.lmr.fr:8443";
      description = "Cluster's stable control-plane endpoint (host:port), fronting every control-plane node's local haproxy.";
    };
    serviceSubnet = lib.mkOption {
      type = lib.types.str;
      default = "172.16.42.0/24";
      description = "Kubernetes service subnet (kubeadm's `networking.serviceSubnet`).";
    };
    podSubnet = lib.mkOption {
      type = lib.types.str;
      default = "10.42.0.0/16";
      description = "Kubernetes pod subnet (kubeadm's `networking.podSubnet`).";
    };
    clusterDNS = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "172.16.42.10" ];
      description = "Cluster DNS service IP(s), passed to every node's kubelet config.";
    };
    extraCertSANs = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = ''
        Extra apiserver certificate SANs (hostnames/IPs) beyond the ones
        automatically derived from `masters` (each master's name and
        address), e.g. an internal cluster domain, or reserved
        not-yet-provisioned future node names/IPs.
      '';
    };
    masters = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule {
        options = {
          address = lib.mkOption {
            type = lib.types.str;
            description = "This master's address.";
          };
          etcdMember = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = "Whether this master is a live etcd cluster member (included in etcd's initial-cluster/etcd-servers).";
          };
          haproxyBackend = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = "Whether to include this master as a backend in every node's local haproxy load-balancer.";
          };
        };
      });
      default = { };
      description = ''
        Every control-plane node in the cluster (VM or container), name ->
        address. Used to compute etcd's initial-cluster/etcd-servers, the
        apiserver's certificate SANs, each control-plane node's local
        haproxy backend list, and worker nodes' `--add-host` entries for
        `controlPlaneEndpoint`.
      '';
    };
    workers = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule ({ name, ... }: {
        options = {
          address = lib.mkOption {
            type = lib.types.str;
            description = "This worker's address.";
          };
          secretFile = lib.mkOption {
            type = lib.types.path;
            description = ''
              sops-nix encrypted file containing this node's cluster CA
              material, under the keys `ca_crt` and `ca_key`.
            '';
          };
          dataDir = lib.mkOption {
            type = lib.types.str;
            default = "/nix/var/lib/containers-var/${name}";
            defaultText = lib.literalExpression ''"/nix/var/lib/containers-var/${name}"'';
            description = "Host directory holding this node's persistent state subdirectories.";
          };
          extraVolumes = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [ ];
            description = "Extra volumes, in addition to the ones this preset generates.";
          };
          extraOptions = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [ ];
            description = "Extra `docker run` options, in addition to the ones this preset generates.";
          };
        };
      }));
      default = { };
      description = "Kubernetes worker nodes to run as containers on this host.";
    };
    controlPlanes = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule ({ name, ... }: {
        options = {
          address = lib.mkOption {
            type = lib.types.str;
            description = "This control-plane node's address. Must also appear in `masters.<name>.address`.";
          };
          podCIDR = lib.mkOption {
            type = lib.types.str;
            description = ''
              This node's own pod CIDR (`kubectl get node <name> -o
              jsonpath='{.spec.podCIDR}'`), used to set up a host route so
              the host's iscsid can reach the Longhorn engine's iSCSI
              target IP inside this node's own pod network.
            '';
          };
          dataDir = lib.mkOption {
            type = lib.types.str;
            default = "/nix/var/lib/containers-var/${name}";
            defaultText = lib.literalExpression ''"/nix/var/lib/containers-var/${name}"'';
            description = "Host directory holding this node's persistent state subdirectories (etcd/kubelet/containerd/opt-cni-bin).";
          };
          dataDevice = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            description = ''
              Block device to mount as ext4 at `dataDir`, e.g.
              "/dev/data/${name}" (typically a wiped/reformatted former VM
              root disk). Leave null if `dataDir` is already
              mounted/managed elsewhere.
            '';
          };
          secretFile = lib.mkOption {
            type = lib.types.path;
            description = ''
              sops-nix encrypted file containing this node's full cert
              bundle, under the keys `ca_crt`, `ca_key`, `sa_pub`,
              `sa_key`, `front_proxy_ca_crt`, `front_proxy_ca_key`,
              `etcd_ca_crt` and `etcd_ca_key`.
            '';
          };
          iscsiInitiatorName = lib.mkOption {
            type = lib.types.str;
            example = "iqn.2016-04.com.open-iscsi:srv3";
            description = ''
              iSCSI initiator name for the HOST's own iscsid (services.openiscsi).
              iscsid must run on the true host, not inside the container:
              the kernel's iSCSI netlink socket only exists in init_net, so
              a container with its own macvlan network namespace can never
              reach it.
            '';
          };
          extraVolumes = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [ ];
            description = "Extra volumes, in addition to the ones this preset generates.";
          };
          extraOptions = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [ ];
            description = "Extra `docker run` options, in addition to the ones this preset generates.";
          };
        };
      }));
      default = { };
      description = "Kubernetes control-plane (+etcd) nodes to run as containers on this host.";
    };
  };

  config = lib.mkIf (kn.workers != { } || kn.controlPlanes != { }) {
    assertions = [
      {
        assertion = (lib.length (lib.attrNames (lib.filterAttrs (n: _: lib.hasAttr n kn.controlPlanes) kn.workers))) == 0;
        message = "bcl.role.server.container.kubeletNode: the same name cannot be both a worker and a control-plane.";
      }
      {
        assertion = kn.controlPlanes == { } || (lib.length (lib.attrNames kn.controlPlanes)) <= 1;
        message = "bcl.role.server.container.kubeletNode.controlPlanes: only one control-plane container per host is supported (services.openiscsi is host-wide).";
      }
    ];

    bcl.role.server.container.containers =
      (lib.mapAttrs mkWorkerContainer kn.workers)
      // (lib.mapAttrs mkControlPlaneContainer kn.controlPlanes);

    # Each node's secretFile is decrypted here (rather than requiring every
    # consumer to declare these itself), namespaced by node name (`key =`
    # points back at the actual field name inside the sops file) so
    # multiple node containers on the same host never collide.
    sops.secrets = lib.mkMerge (
      (lib.mapAttrsToList
        (name: w: {
          "${name}-ca_crt" = { sopsFile = w.secretFile; key = "ca_crt"; mode = "0400"; };
          "${name}-ca_key" = { sopsFile = w.secretFile; key = "ca_key"; mode = "0400"; };
        })
        kn.workers)
      ++ (lib.mapAttrsToList
        (name: cp: {
          "${name}-ca_crt" = { sopsFile = cp.secretFile; key = "ca_crt"; mode = "0400"; };
          "${name}-ca_key" = { sopsFile = cp.secretFile; key = "ca_key"; mode = "0400"; };
          "${name}-sa_pub" = { sopsFile = cp.secretFile; key = "sa_pub"; mode = "0400"; };
          "${name}-sa_key" = { sopsFile = cp.secretFile; key = "sa_key"; mode = "0400"; };
          "${name}-front_proxy_ca_crt" = { sopsFile = cp.secretFile; key = "front_proxy_ca_crt"; mode = "0400"; };
          "${name}-front_proxy_ca_key" = { sopsFile = cp.secretFile; key = "front_proxy_ca_key"; mode = "0400"; };
          "${name}-etcd_ca_crt" = { sopsFile = cp.secretFile; key = "etcd_ca_crt"; mode = "0400"; };
          "${name}-etcd_ca_key" = { sopsFile = cp.secretFile; key = "etcd_ca_key"; mode = "0400"; };
        })
        kn.controlPlanes)
    );

    # kubelet (cgroupDriver: cgroupfs) needs to create/manage its own cgroup
    # subtree (/kubepods/...) under whatever cgroup root it sees. Docker's
    # default cgroupns=private only delegates the container's own single
    # leaf cgroup, without enabling controllers for it to create children
    # there - kubelet then fails with "cpu.weight: read-only file system".
    # Rather than using --cgroupns=host + bind-mounting the real host
    # /sys/fs/cgroup (which exposes/shares the host's actual cgroup tree -
    # and would collide if multiple node containers used the same paths),
    # grant proper cgroup v2 delegation to the container's own
    # private/namespaced cgroup via systemd, same mechanism kind/k3d/
    # minikube rely on for Kubernetes-in-Docker.
    systemd.services = lib.mkMerge (
      (lib.mapAttrsToList (name: _: { "docker-${name}".serviceConfig.Delegate = "yes"; }) kn.workers)
      ++ (lib.mapAttrsToList
        (name: cp: {
          "docker-${name}".serviceConfig.Delegate = "yes";

          # Lets the host's iscsid (and hence Longhorn's engine, which
          # nsenters into iscsid's own net+mount namespace to run
          # iscsiadm) reach the Longhorn engine's iSCSI target IP inside
          # this node's own cilium pod network - which is otherwise only
          # routable from inside the node container itself (cilium's VXLAN
          # datapath runs there, not on the host). Routes via this node's
          # own macvlan IP, which the host can already reach directly on
          # `bridge`.
          "bcl-route-${name}-pod-cidr" = {
            description = "Static route to ${name}'s pod CIDR via its macvlan IP";
            after = [ "sys-subsystem-net-devices-${kn.bridge}.device" ];
            bindsTo = [ "sys-subsystem-net-devices-${kn.bridge}.device" ];
            wantedBy = [ "multi-user.target" ];
            serviceConfig = {
              Type = "oneshot";
              RemainAfterExit = true;
              # Full path to the binary, rather than relying on `path`/PATH
              # resolution - systemd failed to locate a bare "ip" at deploy
              # time despite a `path = [ pkgs.iproute2 ];`.
              # `onlink` is required: the macvlan bridge itself has no IPv4
              # address on the host (it's only used to attach macvlan
              # containers), so the kernel can't verify the gateway is
              # on-link and rejects it without this flag.
              ExecStart = "${pkgs.iproute2}/bin/ip route replace ${cp.podCIDR} via ${cp.address} dev ${kn.bridge} onlink";
              ExecStop = "${pkgs.iproute2}/bin/ip route del ${cp.podCIDR} via ${cp.address} dev ${kn.bridge} onlink";
            };
          };
        })
        kn.controlPlanes)
    );

    systemd.tmpfiles.rules = lib.concatLists (lib.mapAttrsToList
      (name: cp: [
        "d ${cp.dataDir}/etcd 0700 root root -"
        "d ${cp.dataDir}/kubelet 0755 root root -"
        "d ${cp.dataDir}/containerd 0755 root root -"
        "d ${cp.dataDir}/opt-cni-bin 0755 root root -"
      ])
      kn.controlPlanes);

    fileSystems = lib.mkMerge (lib.mapAttrsToList
      (name: cp: lib.mkIf (cp.dataDevice != null) {
        "${cp.dataDir}" = { device = cp.dataDevice; fsType = "ext4"; };
      })
      kn.controlPlanes);

    # iscsid MUST run on the true host (not inside the control-plane
    # container) because the kernel's iSCSI netlink socket (NETLINK_ISCSI,
    # used to register new sessions) only exists in init_net - a container
    # with its own macvlan network namespace can never reach it, causing
    # iscsid to crash-loop with "Can not bind IPC socket" / sessions to
    # fail with ECONNREFUSED. Only one control-plane container per host is
    # supported (enforced by the assertion above), since this is a single
    # host-wide setting.
    services.openiscsi = lib.mkIf (kn.controlPlanes != { }) {
      enable = true;
      name = (lib.head (lib.attrValues kn.controlPlanes)).iscsiInitiatorName;
    };
  };
}
