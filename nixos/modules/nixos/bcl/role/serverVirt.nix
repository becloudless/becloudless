{ config, lib, pkgs, ... }:
let
  cfg = config.bcl.role.serverVirt;
  bridgeName = name: "br${name}";
in
{
  options.bcl.role.serverVirt = {
    vlans = lib.mkOption {
      type = lib.types.attrsOf (lib.types.ints.between 1 4094);
      default = {};
      description = ''
        Declarative 802.1Q VLAN sub-interfaces stacked on top of
        `bcl.network.interface`. Each attribute name is used as the VLAN's
        netdev/interface name, and its value is the VLAN id (e.g.
        `vlan41 = 41;`). Each VLAN gets its own bridge (`br<name>`) that
        VMs can attach to (see `bcl.vm.vms.<name>.bridgeName`). The host
        itself has no IP address on these VLANs/bridges, only VMs do.
      '';
    };
  };

  config = lib.mkMerge [
    { bcl.role.knownRoles = [ "serverVirt" ]; }
    (lib.mkIf (config.bcl.role.name == "serverVirt") {

    bcl.diskSystem.encrypted = true;
    bcl.boot.ssh = true; # give password for disk encryption on boot

    bcl.role.setAdminPassword = true; # being able to log in to console
    security.sudo.wheelNeedsPassword = false;

    environment.systemPackages = with pkgs; [
      virtiofsd # folder mounting for VMs
      ssh-to-age
      mergerfs
    ];

    bcl.network = {
      bridge = true; # so VMs and containers can attach to the untagged network
    };

    services.resolved.dnssec = "true";
    networking.firewall.enable = false;
  })
    (lib.mkIf (cfg.vlans != {}) {
      systemd.network.enable = true;

      systemd.network.netdevs = lib.mkMerge [
        (lib.mapAttrs (name: vlanId: {
          netdevConfig = {
            Kind = "vlan";
            Name = name;
          };
          vlanConfig.Id = vlanId;
        }) cfg.vlans)
        (lib.mapAttrs' (name: _:
          lib.nameValuePair (bridgeName name) {
            netdevConfig = {
              Kind = "bridge";
              Name = bridgeName name;
            };
          }
        ) cfg.vlans)
      ];

      systemd.network.networks = lib.mkMerge [
        (lib.mapAttrs (name: _: {
          matchConfig.Name = name;
          networkConfig.Bridge = bridgeName name;
        }) cfg.vlans)
        (lib.mapAttrs' (name: _:
          lib.nameValuePair (bridgeName name) {
            matchConfig.Name = bridgeName name;
            networkConfig.IgnoreCarrierLoss = true;
          }
        ) cfg.vlans)
        # Attaches these VLANs to the trunk interface's own .network file
        # (see bcl.network's "bcl-physical" key); `vlan` is a listOf str
        # NixOS option, so this merges additively with bcl.network's own
        # definition of the same "bcl-physical" key instead of conflicting.
        { bcl-physical.vlan = lib.attrNames cfg.vlans; }
      ];
    })
  ];
}
