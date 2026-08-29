{ config, lib, ... }:
let
  cfg = config.bcl.vlan;
  bridgeName = name: "br-${name}";
  vlanSubmodule = lib.types.submodule {
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
        type = lib.types.listOf lib.types.str;
        default = [];
        description = "Static addresses (CIDR notation) to assign to this VLAN (or its bridge).";
      };
      routes = lib.mkOption {
        type = lib.types.listOf lib.types.attrs;
        default = [];
        description = "Extra systemd-networkd [Route] sections for this VLAN (or its bridge).";
      };
    };
  };
  bridgedVlans = lib.filterAttrs (_: vlan: vlan.bridge) cfg.vlans;
in
{
  options.bcl.vlan = {
    interface = lib.mkOption {
      type = lib.types.str;
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
        } // (lib.optionalAttrs vlan.bridge { Bridge = bridgeName name; });
        address = lib.optionals (!vlan.bridge) vlan.address;
        routes = lib.optionals (!vlan.bridge) vlan.routes;
      }) cfg.vlans)
      // (lib.mapAttrs' (name: vlan:
        lib.nameValuePair (bridgeName name) {
          matchConfig.Name = bridgeName name;
          networkConfig = {
            IgnoreCarrierLoss = true;
            KeepConfiguration = true;
          };
          address = vlan.address;
          routes = vlan.routes;
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
