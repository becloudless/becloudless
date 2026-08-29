{ config, lib, ... }:
let
  cfg = config.bcl.network;
in
{
  options.bcl.network = {
    interface = lib.mkOption {
      type = lib.types.str;
      default = "en* eth*";
      description = ''
        systemd-networkd match pattern for the physical interface carrying
        this host's untagged (native VLAN) network (e.g. "eth0" or "en* eth*").
      '';
    };

    address = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = "Static addresses (CIDR notation) for the untagged network.";
    };

    gateway = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Default gateway for the untagged network.";
    };

    nameservers = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = "DNS nameservers to use for this host.";
    };
  };

  ####################

  config = lib.mkIf (cfg.address != []) {
    systemd.network.enable = true;
    networking.nameservers = cfg.nameservers;

    # NOTE: keyed as "bcl-physical" so this merges with any bcl.vlan trunk
    # config for the same physical interface into a single systemd-networkd
    # .network file, instead of two separate files both matching cfg.interface
    # (systemd-networkd only applies the first matching file per interface).
    systemd.network.networks.bcl-physical = {
      matchConfig.Name = cfg.interface;
      networkConfig = {
        IgnoreCarrierLoss = true;
        KeepConfiguration = true;
      };
      address = cfg.address;
      routes = lib.optional (cfg.gateway != null) {
        Gateway = cfg.gateway;
        GatewayOnLink = true;
      };
    };
  };
}
