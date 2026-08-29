{ config, lib, ... }:
let
  cfg = config.bcl.network;
  bridgeName = "br0";
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

    bridge = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Whether to create a Linux bridge on top of the untagged network so
        VMs (or containers) can attach to it, in addition to the host itself.
        When true, the bridge interface is named "br0" and `address`/`routes`
        are applied to that bridge instead of the raw physical interface.
      '';
    };

    address = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Static address (CIDR notation) for the untagged network.";
      example = "192.168.1.20/24";
    };

    gateway = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = lib.mapNullable (a: lib.bcl.net.cidrhost a 1) cfg.address;
      defaultText = lib.literalExpression "first address of `bcl.network.address`";
      description = "Default gateway for the untagged network.";
    };

    nameservers = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = lib.optional (cfg.address != null) (lib.bcl.net.cidrhost cfg.address 1);
      defaultText = lib.literalExpression "[ first address of `bcl.network.address` ]";
      description = "DNS nameservers to use for this host.";
    };
  };

  ####################

  config = lib.mkIf (cfg.address != null) {
    systemd.network.enable = true;
    networking.nameservers = cfg.nameservers;

    systemd.network.netdevs = lib.mkIf cfg.bridge {
      ${bridgeName}.netdevConfig = {
        Kind = "bridge";
        Name = bridgeName;
      };
    };

    # NOTE: keyed as "bcl-physical" so this merges with any bcl.vlan trunk
    # config for the same physical interface into a single systemd-networkd
    # .network file, instead of two separate files both matching cfg.interface
    # (systemd-networkd only applies the first matching file per interface).
    systemd.network.networks.bcl-physical = {
      matchConfig.Name = cfg.interface;
      networkConfig = {
        IgnoreCarrierLoss = true;
        KeepConfiguration = true;
      } // (lib.optionalAttrs cfg.bridge { Bridge = bridgeName; });
      address = lib.optionals (!cfg.bridge) [ cfg.address ];
      routes = lib.optionals (!cfg.bridge) (lib.optional (cfg.gateway != null) {
        Gateway = cfg.gateway;
        GatewayOnLink = true;
      });
    };

    systemd.network.networks.bcl-network-bridge = lib.mkIf cfg.bridge {
      matchConfig.Name = bridgeName;
      networkConfig = {
        IgnoreCarrierLoss = true;
        KeepConfiguration = true;
      };
      address = [ cfg.address ];
      routes = lib.optional (cfg.gateway != null) {
        Gateway = cfg.gateway;
        GatewayOnLink = true;
      };
    };
  };
}
