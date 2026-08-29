{ lib, config, ... }: let
  cfg = config.bcl.cluster;
  nodeNumber = lib.strings.toInt (builtins.elemAt (builtins.match "(.*[^0-9])?([0-9]+)" config.networking.hostName) 1);
  nodeIp = lib.bcl.net.cidrhost cfg.cidr nodeNumber;
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
        Each VLAN will be created as a bridge (see bcl.vlan) that VMs can attach to via their `bridgeName`.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    bcl.network = {
      bridge = true; # so VMs and containers can attach to the untagged network
      address = "${nodeIp}/${toString (lib.bcl.net.cidrPrefixLength cfg.cidr)}";
      gateway = lib.bcl.net.cidrhost cfg.cidr 1; # gateway is always the first address in the cluster network by default
      nameservers = cfg.nameservers;
    };

    bcl.vlan = lib.mapAttrs (_: vlan: lib.mkIf (vlan.address != null) {
      address = "${lib.bcl.net.cidrhost vlan.address nodeNumber}/${toString (lib.bcl.net.cidrPrefixLength vlan.address)}";
    }) cfg.vlans; 

  };
}