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
        Self define configuration as part of a cluster, from the hostname.
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
  };

  config = lib.mkIf cfg.enable {
    bcl.network = {
      bridge = true; # so VMs and containers can attach to the untagged network
      address = "${nodeIp}/${toString (lib.bcl.net.cidrPrefixLength cfg.cidr)}";
    };
  };
}
