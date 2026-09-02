{ config, lib, pkgs, ... }:
let
  cfg = config.bcl.role.serverVirt;
  vlanName = id: "vlan${toString id}";
  bridgeName = id: "br${toString id}";
in
{
  options.bcl.role.serverVirt = {
    vlans = lib.mkOption {
      type = lib.types.listOf (lib.types.ints.between 1 4094);
      default = [];
      description = ''
        Declarative 802.1Q VLAN sub-interfaces stacked on top of
        `bcl.network.interface` (e.g. `[ 41 43 ]`). Each VLAN gets its own
        bridge (`br<id>`) that VMs can attach to (see
        `bcl.role.serverVirt.vms.<name>.bridgeName`). The host itself has no
        IP address on these VLANs/bridges, only VMs do.
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

    bcl.diskSystem.nixSize = "50G";

    bcl.network = {
      bridge = true; # so VMs can attach to the untagged network
    };


    services.resolved.dnssec = "true";
    networking.firewall.enable = false;
  })
    (lib.mkIf (cfg.vlans != []) {
      systemd.network.enable = true;

      systemd.network.netdevs = lib.mkMerge [
        (lib.listToAttrs (map (id: lib.nameValuePair (vlanName id) {
          netdevConfig = {
            Kind = "vlan";
            Name = vlanName id;
          };
          vlanConfig.Id = id;
        }) cfg.vlans))
        (lib.listToAttrs (map (id: lib.nameValuePair (bridgeName id) {
          netdevConfig = {
            Kind = "bridge";
            Name = bridgeName id;
          };
        }) cfg.vlans))
      ];

      systemd.network.networks = lib.mkMerge [
        (lib.listToAttrs (map (id: lib.nameValuePair (vlanName id) {
          matchConfig.Name = vlanName id;
          networkConfig.Bridge = bridgeName id;
        }) cfg.vlans))
        (lib.listToAttrs (map (id: lib.nameValuePair (bridgeName id) {
          matchConfig.Name = bridgeName id;
          networkConfig.IgnoreCarrierLoss = true;
        }) cfg.vlans))
        # Attaches these VLANs to the trunk interface's own .network file
        # (see bcl.network's "net" key); `vlan` is a listOf str NixOS
        # option, so this merges additively with bcl.network's own
        # definition of the same "net" key instead of conflicting.
        { net.vlan = map vlanName cfg.vlans; }
      ];
    })
  ];
}
