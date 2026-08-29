{ lib, config, ... }: let
  cfg = config.bcl.cluster;
  nodeNumber = lib.strings.toInt (builtins.elemAt (builtins.match "(.*[^0-9])?([0-9]+)" config.networking.hostName) 1);
  nodeIp = lib.bcl.net.cidrhost cfg.cidr nodeNumber;

  # Derives a VLAN's /24 subnet from its id, reusing the first two octets of
  # the cluster's own CIDR (e.g. cidr "192.168.41.0/22" + vlan id 11 ->
  # "192.168.11.0/24"), matching the convention used in the network's
  # RouterOS config (VLAN 11 -> 192.168.11.0/24, VLAN 22 -> 192.168.22.0/24).
  cidrBase = lib.concatStringsSep "." (lib.take 2 (lib.strings.splitString "." (lib.bcl.net.cidrAddress cfg.cidr)));
  vlanCidr = id: "${cidrBase}.${toString id}.0/24";
in
{
  options.bcl.cluster = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Self define confiuration as part of a cluster, from the hostname.
        hostname must be of the form <group><number> (e.g. "srv25" or "srv26").
        when true, network, vlan are derived from the hostname number.
      '';
    };
    cidr = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = ''
        CIDR of the cluster network, e.g. 
        '';
    };
    # list of vlanName ->  vlanId
    vlans = lib.mkOption {
      type = lib.types.attrsOf lib.types.int;
      default = {};
      description = ''
        List of VLANs in the cluster, as a map of vlanName -> vlanId.
        Each VLAN's subnet, gateway and nameservers are derived from its id
        (see `vlanCidr` above); each VLAN is created as a bridge (see
        bcl.network.vlans) that VMs can attach to via their `bridgeName`.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    bcl.network = {
      bridge = true; # so VMs and containers can attach to the untagged network
      address = "${nodeIp}/${toString (lib.bcl.net.cidrPrefixLength cfg.cidr)}";
    };

    bcl.network.vlans = lib.mapAttrs (_: id: {
      inherit id;
      address = "${lib.bcl.net.cidrhost (vlanCidr id) nodeNumber}/24";
    }) cfg.vlans;

  };
}