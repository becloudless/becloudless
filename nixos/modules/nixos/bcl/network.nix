{ config, lib, ... }:
let
  cfg = config.bcl.network;

  # Shared option builders: `gateway`/`nameservers` default to the first host
  # IP of `address`'s CIDR when unset. Used for both the untagged network
  # (bcl.network.*) and each declared VLAN (bcl.network.vlans.*).
  mkGatewayOption = address: lib.mkOption {
    type = lib.types.nullOr lib.types.str;
    default = lib.mapNullable (a: lib.bcl.net.cidrhost a 1) address;
    defaultText = lib.literalExpression "first address of `address`";
    description = "Default gateway for this network.";
  };
  mkNameserversOption = address: lib.mkOption {
    type = lib.types.listOf lib.types.str;
    default = lib.optional (address != null) (lib.bcl.net.cidrhost address 1);
    defaultText = lib.literalExpression "[ first address of `address` ]";
    description = "DNS nameservers to use for this network.";
  };

  vlanBridgeName = name: "br-${name}";

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
          interface is named `br-<name>` and any `address`/`gateway` are
          applied to that bridge instead of the raw VLAN interface.
        '';
      };
      address = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Static address (CIDR notation) to assign to this VLAN (or its bridge).";
        example = "192.168.10.42/24";
      };
      gateway = mkGatewayOption config.address;
      nameservers = mkNameserversOption config.address;
    };
  });

  # Builds the systemd-networkd netdev/network fragments for a single
  # physical/VLAN interface, optionally bridged so VMs can attach to it.
  # Shared between the untagged network (bcl.network.*) and each declared
  # VLAN (bcl.network.vlans.*) to avoid duplicating this logic twice.
  mkBridgedInterface = { matchName, bridge, bridgeName, address, gateway, nameservers, extraNetworkConfig ? {} }: {
    netdev = lib.optionalAttrs bridge {
      ${bridgeName}.netdevConfig = {
        Kind = "bridge";
        Name = bridgeName;
      };
    };
    interfaceNetwork = {
      matchConfig.Name = matchName;
      networkConfig = {
        IgnoreCarrierLoss = true;
      } // extraNetworkConfig
        // (lib.optionalAttrs bridge { Bridge = bridgeName; })
        // (lib.optionalAttrs (!bridge) { DNS = nameservers; });
      address = lib.optionals (!bridge) (lib.optional (address != null) address);
      routes = lib.optionals (!bridge) (lib.optional (gateway != null) {
        Gateway = gateway;
        GatewayOnLink = true;
      });
    };
    bridgeNetwork = lib.optionalAttrs bridge {
      ${bridgeName} = {
        matchConfig.Name = bridgeName;
        networkConfig = {
          IgnoreCarrierLoss = true;
          KeepConfiguration = true;
          DNS = nameservers;
        };
        address = lib.optional (address != null) address;
        routes = lib.optional (gateway != null) {
          Gateway = gateway;
          GatewayOnLink = true;
        };
      };
    };
  };
in
{
  options.bcl.network = {
    interface = lib.mkOption {
      type = lib.types.str;
      default = "en* eth*";
      description = ''
        systemd-networkd match pattern for the physical interface carrying
        this host's untagged (native VLAN) network, and acting as the trunk
        for any `bcl.network.vlans` (e.g. "eth0" or "en* eth*").
      '';
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

    address = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Static address (CIDR notation) for the untagged network.";
      example = "192.168.1.20/24";
    };

    gateway = mkGatewayOption cfg.address;
    nameservers = mkNameserversOption cfg.address;

    vlans = lib.mkOption {
      type = lib.types.attrsOf vlanSubmodule;
      default = {};
      description = ''
        Declarative 802.1Q VLAN sub-interfaces stacked on top of
        `bcl.network.interface`. Each attribute name is used as the VLAN's
        netdev/interface name.
      '';
    };
  };

  ####################

  config = let
    untagged = mkBridgedInterface {
      matchName = cfg.interface;
      bridge = cfg.bridge;
      bridgeName = "br0";
      address = cfg.address;
      gateway = cfg.gateway;
      nameservers = cfg.nameservers;
      extraNetworkConfig = lib.optionalAttrs (cfg.vlans != {}) { VLAN = lib.attrNames cfg.vlans; };
    };
    vlanResults = lib.mapAttrs (name: vlan: mkBridgedInterface {
      matchName = name;
      bridge = vlan.bridge;
      bridgeName = vlanBridgeName name;
      address = vlan.address;
      gateway = vlan.gateway;
      nameservers = vlan.nameservers;
    }) cfg.vlans;
  in lib.mkIf (cfg.address != null || cfg.bridge || cfg.vlans != {}) {
    systemd.network.enable = true;
    networking.nameservers = cfg.nameservers;

    systemd.network.netdevs =
      untagged.netdev
      // (lib.mapAttrs (name: vlan: {
        netdevConfig = {
          Kind = "vlan";
          Name = name;
        };
        vlanConfig.Id = vlan.id;
      }) cfg.vlans)
      // (lib.foldl' (acc: r: acc // r.netdev) {} (lib.attrValues vlanResults));

    systemd.network.networks =
      # NOTE: keyed as "bcl-physical" so the untagged network config and the
      # VLAN trunk config both land in the same systemd-networkd .network
      # file for the shared physical interface (systemd-networkd only
      # applies the first matching file per interface).
      { bcl-physical = untagged.interfaceNetwork; }
      // untagged.bridgeNetwork
      // (lib.mapAttrs (name: _: vlanResults.${name}.interfaceNetwork) cfg.vlans)
      // (lib.foldl' (acc: r: acc // r.bridgeNetwork) {} (lib.attrValues vlanResults));
  };
}
