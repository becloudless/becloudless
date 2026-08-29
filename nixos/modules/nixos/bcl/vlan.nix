{ config, lib, ... }:
let
  cfg = config.bcl.vlan;
  bridgeName = name: "br-${name}";
  vlanSubmodule = lib.types.submodule ({ config, ... }: {
    options = {
      id = lib.mkOption {
        type = lib.types.ints.between 1 4094;
        description = "802.1Q VLAN ID.";
      };
      bridge = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Whether to create a Linux bridge on top of this VLAN so VMs (or
          containers) can attach to it. When true (the default), the bridge
          interface is named `br-<name>` and any `address`/`routes` are
          applied to that bridge instead of the raw VLAN interface.
        '';
      };
      address = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Static address (CIDR notation) to assign to this VLAN (or its bridge).";
        example = "192.168.10.42/24";
      };
      gateway = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = lib.mapNullable (a: lib.bcl.net.cidrhost a 1) config.address;
        defaultText = lib.literalExpression "first address of `address`";
        description = "Default gateway for this VLAN (or its bridge).";
      };
      nameservers = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = lib.optional (config.address != null) (lib.bcl.net.cidrhost config.address 1);
        defaultText = lib.literalExpression "[ first address of `address` ]";
        description = "DNS nameservers to use for this VLAN (or its bridge).";
      };
    };
  });
  bridgedVlans = lib.filterAttrs (_: vlan: vlan.bridge) cfg.vlans;
in
{
  options.bcl.vlan = {
    interface = lib.mkOption {
      type = lib.types.str;
      default = "en* eth*";
      description = ''
        systemd-networkd match pattern for the physical interface the VLANs
        are stacked on top of (e.g. "eth0" or "en* eth*").
      '';
    };

    vlans = lib.mkOption {
      type = lib.types.attrsOf vlanSubmodule;
      default = {};
      description = ''
        Declarative 802.1Q VLAN sub-interfaces stacked on top of
        `bcl.vlan.interface`. Each attribute name is used as the VLAN's
        netdev/interface name.
      '';
    };
  };

  ####################

  config = lib.mkIf (cfg.vlans != {}) {
    systemd.network.enable = true;

    systemd.network.netdevs =
      (lib.mapAttrs (name: vlan: {
        netdevConfig = {
          Kind = "vlan";
          Name = name;
        };
        vlanConfig.Id = vlan.id;
      }) cfg.vlans)
      // (lib.mapAttrs' (name: _:
        lib.nameValuePair (bridgeName name) {
          netdevConfig = {
            Kind = "bridge";
            Name = bridgeName name;
          };
        }
      ) bridgedVlans);

    systemd.network.networks =
      (lib.mapAttrs (name: vlan: {
        matchConfig.Name = name;
        networkConfig = {
          IgnoreCarrierLoss = true;
        } // (lib.optionalAttrs vlan.bridge { Bridge = bridgeName name; })
          // (lib.optionalAttrs (!vlan.bridge) { DNS = vlan.nameservers; });
        address = lib.optionals (!vlan.bridge) (lib.optional (vlan.address != null) vlan.address);
        routes = lib.optionals (!vlan.bridge) (lib.optional (vlan.gateway != null) {
          Gateway = vlan.gateway;
          GatewayOnLink = true;
        });
      }) cfg.vlans)
      // (lib.mapAttrs' (name: vlan:
        lib.nameValuePair (bridgeName name) {
          matchConfig.Name = bridgeName name;
          networkConfig = {
            IgnoreCarrierLoss = true;
            KeepConfiguration = true;
            DNS = vlan.nameservers;
          };
          address = lib.optional (vlan.address != null) vlan.address;
          routes = lib.optional (vlan.gateway != null) {
            Gateway = vlan.gateway;
            GatewayOnLink = true;
          };
        }
      ) bridgedVlans)
      // {
        # NOTE: keyed as "bcl-physical" (same key used by bcl.network) so this
        # merges into a single systemd-networkd .network file for the shared
        # physical interface, rather than two separate files both matching
        # cfg.interface (only one file would be applied per interface otherwise).
        bcl-physical = {
          matchConfig.Name = cfg.interface;
          networkConfig = {
            IgnoreCarrierLoss = true;
            VLAN = lib.attrNames cfg.vlans;
          };
        };
      };
  };
}
