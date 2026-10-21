{ config, lib, pkgs, ... }:
let
  cfg = config.bcl.role.serverKube;
  endpoint = "kube.${config.bcl.global.domain}:8443"; # the local haproxy, see serverKubeHap.nix
in
{
  config = lib.mkIf (config.bcl.role.name == "serverKube" && cfg.worker) {

    # Only the cluster CA is needed: the kubelet client certificate is signed locally (same token-free join as the
    # container kubelet nodes), there is no bootstrap token to distribute.
    sops.secrets."ca_crt" = {
      sopsFile = config.bcl.role.secretFile;
      mode = "0600";
    };

    sops.secrets."ca_key" = {
      sopsFile = config.bcl.role.secretFile;
      mode = "0600";
    };

    environment.etc."kubernetes/kubeadm-worker.yaml".text = ''
      apiVersion: kubeadm.k8s.io/v1beta3
      kind: ClusterConfiguration
      kubernetesVersion: ${pkgs.kubernetes.version}
      controlPlaneEndpoint: ${endpoint}
    '';

    environment.etc."kubernetes/kubelet-config.yaml".text = ''
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
      cgroupDriver: systemd
      containerRuntimeEndpoint: unix:///var/run/crio/crio.sock
      clusterDNS:
      - 172.16.42.10
      clusterDomain: cluster.local
      resolvConf: /run/systemd/resolve/resolv.conf
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
    '';

    systemd.services."kube-worker-kubeconfig" = {
      path = [ pkgs.kubernetes ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        mkdir -p /etc/kubernetes/pki
        cp ${config.sops.secrets."ca_crt".path} /etc/kubernetes/pki/ca.crt
        cp ${config.sops.secrets."ca_key".path} /etc/kubernetes/pki/ca.key
        kubeadm kubeconfig user \
          --client-name "system:node:${config.networking.hostName}" \
          --org system:nodes \
          --config /etc/kubernetes/kubeadm-worker.yaml \
          > /etc/kubernetes/kubelet.conf.new
        mv /etc/kubernetes/kubelet.conf.new /etc/kubernetes/kubelet.conf
        chmod 0600 /etc/kubernetes/kubelet.conf
      '';
      unitConfig.ConditionPathExists = [
        config.sops.secrets."ca_crt".path
        config.sops.secrets."ca_key".path
      ];
      after = [ "network-online.target" "time-sync.target" ];
      wants = [ "network-online.target" "time-sync.target" ];
      before = [ "kubelet.service" ];
      requiredBy = [ "kubelet.service" ];
    };

    systemd.services."kubelet" = {
      serviceConfig.ExecStart = "${pkgs.kubernetes}/bin/kubelet --config=/etc/kubernetes/kubelet-config.yaml --kubeconfig=/etc/kubernetes/kubelet.conf";
      after = [ "crio.service" "haproxy-apiserver.service" "kube-worker-kubeconfig.service" ];
      wants = [ "crio.service" "haproxy-apiserver.service" ];
      wantedBy = [ "multi-user.target" ];
    };
  };
}
