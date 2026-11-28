{ config, lib, pkgs, ... }:
let
  cfg = config.bcl.role.kube;
  nodeIp = n: lib.bcl.net.ipAdd cfg.firstNodeIp (n - 1);
  nodeName = n: "${cfg.clusterName}${toString n}";
  nodeNumber = lib.strings.toInt (builtins.substring ((builtins.stringLength config.networking.hostName) - 1) (-1) config.networking.hostName);
  myIp = nodeIp nodeNumber;
  peerUrl = "https://${myIp}:2380";
  otherMasterEndpoints = map (n: "https://${nodeIp n}:2379")
    (lib.filter (n: n != nodeNumber) (lib.range 1 cfg.masterNodeCount));

  etcdJoinExistingCluster = pkgs.writeShellApplication {
    name = "etcd-join-existing-cluster";
    runtimeInputs = [ pkgs.etcd pkgs.kubernetes pkgs.gawk pkgs.gnused pkgs.coreutils ];
    text = lib.bcl.kube.etcdJoinExistingClusterScript {
      memberName = nodeName nodeNumber;
      inherit peerUrl otherMasterEndpoints;
      staticConfigPath = lib.bcl.kube.kubeadmStaticConfigPath;
      initConfigPath = lib.bcl.kube.kubeadmInitConfigPath;
      joinAsLearner = true;
    };
  };

  etcdPromoteLearner = pkgs.writeShellApplication {
    name = "etcd-promote-learner";
    runtimeInputs = [ pkgs.etcd pkgs.gawk pkgs.coreutils ];
    text = lib.bcl.kube.etcdPromoteLearnerScript {
      inherit peerUrl otherMasterEndpoints;
    };
  };
in
{
  config = lib.mkIf (config.bcl.role.name == "kube" && !cfg.worker) {
    # Before `kubeadm init`: decides if the etcd of the node starts a new cluster or joins the running one, as a learner.
    systemd.services."kubeadm".preStart = "${etcdJoinExistingCluster}/bin/etcd-join-existing-cluster";

    # The node joined the running etcd cluster as a learner, it votes once promoted. Not ordered after `kubeadm`: it waits for the
    # control plane of the node, which may need the promotion.
    systemd.services."etcd-promote-learner" = lib.mkIf (otherMasterEndpoints != [ ]) {
      description = "Promote the etcd member of the node when it joined the running cluster as a learner";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        ExecStart = "${etcdPromoteLearner}/bin/etcd-promote-learner";
        Restart = "on-failure";
        RestartSec = 30;
      };
    };
  };
}
