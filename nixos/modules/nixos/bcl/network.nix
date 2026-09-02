{ config, lib, ... }:
let
  cfg = config.bcl.network;

  # Effective address: explicit `address` takes precedence; otherwise, if
  # `cidr` is set, derive it from the hostname's trailing digits (see
  # `bcl.network.cidr`'s description).
  effectiveAddress =
    if cfg.address != null then cfg.address
    else if cfg.cidr != null then lib.bcl.net.cidrHostFromHostname cfg.cidr config.networking.hostName
    else null;
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
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Static address (CIDR notation).";
      example = "192.168.1.20/24";
    };

    cidr = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = ''
        CIDR of the network.
        Used to derive the host's IP address from the hostname using last digits.
        (e.g. hostname 'srv25' with cidr '192.168.1.0/24' gives address '192.168.1.25/24').
      '';
      example = "192.168.1.0/24";
    };

    bridge = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Whether to create a Linux bridge on top of the untagged network so
        VMs (or containers) can attach to it, in addition to the host itself.
        When true, the bridge interface is named "br0" and `address`/`gateway`
        are applied to that bridge instead of the raw physical interface.
      '';
    };

    gateway = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = lib.mapNullable (a: lib.bcl.net.cidrhost a (-2)) effectiveAddress;
      defaultText = lib.literalExpression "last usable address of `bcl.network.address`/`bcl.network.cidr`";
      description = "Default gateway for the untagged network.";
    };

    nameservers = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = lib.optional (effectiveAddress != null) (lib.bcl.net.cidrhost effectiveAddress 1);
      defaultText = lib.literalExpression "[ first address of `bcl.network.address`/`bcl.network.cidr` ]";
      description = "DNS nameservers to use for this host.";
    };
  };

  ####################

  config = lib.mkMerge [
    {
      assertions = [
        {
          assertion = !(cfg.address != null && cfg.cidr != null);
          message = "bcl.network.address and bcl.network.cidr are mutually exclusive; unset one of them.";
        }
      ];
    }
    (lib.mkIf (effectiveAddress != null || cfg.bridge) {
    systemd.network.enable = true;
    networking.nameservers = cfg.nameservers;

    systemd.network.netdevs = lib.mkIf cfg.bridge {
      br0.netdevConfig = {
        Kind = "bridge";
        Name = "br0";
      };
    };

    # NOTE: keyed as "net" so this merges with any other module (e.g.
    # hardware-specific overrides, bcl.role.serverVirt's VLAN trunk config)
    # targeting the same physical interface into a single systemd-networkd
    # .network file, instead of two separate files both matching
    # cfg.interface (systemd-networkd only applies the first matching file
    # per interface).
    systemd.network.networks.net = {
      matchConfig.Name = cfg.interface;
      networkConfig = {
        IgnoreCarrierLoss = true;
      } // (lib.optionalAttrs cfg.bridge { Bridge = "br0"; })
        // (lib.optionalAttrs (!cfg.bridge) { DNS = cfg.nameservers; });
      address = lib.optionals (!cfg.bridge) (lib.optional (effectiveAddress != null) effectiveAddress);
      routes = lib.optionals (!cfg.bridge) (lib.optional (cfg.gateway != null) {
        Gateway = cfg.gateway;
        GatewayOnLink = true;
      });
    };

    systemd.network.networks.br0 = lib.mkIf cfg.bridge {
      matchConfig.Name = "br0";
      networkConfig = {
        IgnoreCarrierLoss = true;
        KeepConfiguration = true;
        DNS = cfg.nameservers;
      };
      address = lib.optional (effectiveAddress != null) effectiveAddress;
      routes = lib.optional (cfg.gateway != null) {
        Gateway = cfg.gateway;
        GatewayOnLink = true;
      };
    };
    })
  ];
}
