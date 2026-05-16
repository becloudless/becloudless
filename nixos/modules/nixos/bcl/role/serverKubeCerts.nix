{ config, lib, pkgs, ... }:
{
  config = lib.mkIf (config.bcl.role.name == "serverKube") {

    sops.secrets."ca_crt" = {
      sopsFile = config.bcl.role.secretFile;
      mode = "0600";
    };

    sops.secrets."ca_key" = {
      sopsFile = config.bcl.role.secretFile;
      mode = "0600";
    };

    sops.secrets."sa_pub" = {
      sopsFile = config.bcl.role.secretFile;
      mode = "0600";
    };

    sops.secrets."sa_key" = {
      sopsFile = config.bcl.role.secretFile;
      mode = "0600";
    };

    sops.secrets."front_proxy_ca_crt" = {
      sopsFile = config.bcl.role.secretFile;
      mode = "0600";
    };

    sops.secrets."front_proxy_ca_key" = {
      sopsFile = config.bcl.role.secretFile;
      mode = "0600";
    };

    sops.secrets."etcd_ca_crt" = {
      sopsFile = config.bcl.role.secretFile;
      mode = "0600";
    };

    sops.secrets."etcd_ca_key" = {
      sopsFile = config.bcl.role.secretFile;
      mode = "0600";
    };

    systemd.services."kube-certs" = {
      serviceConfig = {
        Type = "oneshot";
      };
      script = ''
        mkdir -p /etc/kubernetes/pki/etcd
        cp ${config.sops.secrets."ca_crt".path} /etc/kubernetes/pki/ca.crt
        cp ${config.sops.secrets."ca_key".path} /etc/kubernetes/pki/ca.key
        cp ${config.sops.secrets."sa_pub".path} /etc/kubernetes/pki/sa.pub
        cp ${config.sops.secrets."sa_key".path} /etc/kubernetes/pki/sa.key
        cp ${config.sops.secrets."front_proxy_ca_crt".path} /etc/kubernetes/pki/front-proxy-ca.crt
        cp ${config.sops.secrets."front_proxy_ca_key".path} /etc/kubernetes/pki/front-proxy-ca.key
        cp ${config.sops.secrets."etcd_ca_crt".path} /etc/kubernetes/pki/etcd/ca.crt
        cp ${config.sops.secrets."etcd_ca_key".path} /etc/kubernetes/pki/etcd/ca.key
      '';
      unitConfig = {
        ConditionPathExists = [
          config.sops.secrets."ca_crt".path
          config.sops.secrets."ca_key".path
          config.sops.secrets."sa_pub".path
          config.sops.secrets."sa_key".path
          config.sops.secrets."front_proxy_ca_crt".path
          config.sops.secrets."front_proxy_ca_key".path
          config.sops.secrets."etcd_ca_crt".path
          config.sops.secrets."etcd_ca_key".path
        ];
      };
      before = [ "kubeadm.service" ];
      requiredBy = [ "kubeadm.service" ];
    };
  };
}