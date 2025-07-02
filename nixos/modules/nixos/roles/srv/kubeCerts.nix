{ config, lib, pkgs, ... }:
let
  clusterNumber = builtins.substring ((builtins.stringLength config.networking.hostName) -2) 1 config.networking.hostName;
in
{
  config = lib.mkIf (config.bcl.role.name == "srv") {

    sops.secrets."k${clusterNumber}_ca_crt" = {
      sopsFile = ../srv.secrets.yaml;
      mode = "0600";
    };

    sops.secrets."k${clusterNumber}_ca_key" = {
      sopsFile = ../srv.secrets.yaml;
      mode = "0600";
    };


    sops.secrets."k${clusterNumber}_sa_pub" = {
      sopsFile = ../srv.secrets.yaml;
      mode = "0600";
    };

    sops.secrets."k${clusterNumber}_sa_key" = {
      sopsFile = ../srv.secrets.yaml;
      mode = "0600";
    };

    sops.secrets."k${clusterNumber}_front_proxy_ca_crt" = {
      sopsFile = ../srv.secrets.yaml;
      mode = "0600";
    };

    sops.secrets."k${clusterNumber}_front_proxy_ca_key" = {
      sopsFile = ../srv.secrets.yaml;
      mode = "0600";
    };

    sops.secrets."k${clusterNumber}_etcd_ca_crt" = {
      sopsFile = ../srv.secrets.yaml;
      mode = "0600";
    };

    sops.secrets."k${clusterNumber}_etcd_ca_key" = {
      sopsFile = ../srv.secrets.yaml;
      mode = "0600";
    };

    systemd.services."kube-certs" = {
      serviceConfig = {
        Type = "oneshot";
      };
      script = ''
        mkdir -p /etc/kubernetes/pki/etcd
        cp ${config.sops.secrets."k${clusterNumber}_ca_crt".path} /etc/kubernetes/pki/ca.crt
        cp ${config.sops.secrets."k${clusterNumber}_ca_key".path} /etc/kubernetes/pki/ca.key
        cp ${config.sops.secrets."k${clusterNumber}_sa_pub".path} /etc/kubernetes/pki/sa.pub
        cp ${config.sops.secrets."k${clusterNumber}_sa_key".path} /etc/kubernetes/pki/sa.key
        cp ${config.sops.secrets."k${clusterNumber}_front_proxy_ca_crt".path} /etc/kubernetes/pki/front-proxy-ca.crt
        cp ${config.sops.secrets."k${clusterNumber}_front_proxy_ca_key".path} /etc/kubernetes/pki/front-proxy-ca.key
        cp ${config.sops.secrets."k${clusterNumber}_etcd_ca_crt".path} /etc/kubernetes/pki/etcd/ca.crt
        cp ${config.sops.secrets."k${clusterNumber}_etcd_ca_key".path} /etc/kubernetes/pki/etcd/ca.key
      '';
      unitConfig = {
        ConditionPathExists = [
          config.sops.secrets."k${clusterNumber}_ca_crt".path
          config.sops.secrets."k${clusterNumber}_ca_key".path
          config.sops.secrets."k${clusterNumber}_sa_pub".path
          config.sops.secrets."k${clusterNumber}_sa_key".path
          config.sops.secrets."k${clusterNumber}_front_proxy_ca_crt".path
          config.sops.secrets."k${clusterNumber}_front_proxy_ca_key".path
          config.sops.secrets."k${clusterNumber}_etcd_ca_crt".path
          config.sops.secrets."k${clusterNumber}_etcd_ca_key".path
        ];
      };
      before = [ "kubeadm.service" ];
      requiredBy = [ "kubeadm.service" ];
    };
  };
}