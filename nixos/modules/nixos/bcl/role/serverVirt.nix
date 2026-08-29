{ config, lib, pkgs, ... }:
let
  cfg = config.bcl.role.serverVirt;
  srvNumber = lib.strings.toInt (builtins.elemAt (builtins.match "(.*[^0-9])?([0-9]+)" config.networking.hostName) 1);
  nodeIp = lib.bcl.net.cidrhost cfg.cidr srvNumber;
in
{
  options.bcl.role.serverVirt = {
    # TODO remove and take it from networking range instead
    cidr = lib.mkOption { type = lib.types.str; example = "192.168.41.0/24"; };

    interface = lib.mkOption {
      type = lib.types.str;
      default = "en* eth*";
      description = ''
        systemd-networkd match pattern for the single physical interface used
        for both the host's untagged network (via `bcl.network`) and any
        tagged VLANs (via `bcl.vlan`) attachable to VMs.
      '';
    };

    gateway = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = "192.168.40.10";
      description = "Default gateway for the untagged network.";
    };

    nameservers = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = ["192.168.40.12"];
      description = "DNS nameservers to use for this host.";
    };
  };

  ####################

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

    services.resolved.dnssec = "true";
    networking.firewall.enable = false;

    # Untagged (native VLAN) network: the host's own static ip/route/dns,
    # carried directly on the physical interface (not attached to VMs).
    bcl.network = {
      interface = cfg.interface;
      address = [ "${nodeIp}/${toString (lib.bcl.net.cidrPrefixLength cfg.cidr)}" ];
      gateway = cfg.gateway;
      nameservers = cfg.nameservers;
    };

    # Tagged VLANs stacked on the same physical interface; each becomes a
    # bridge (see bcl.vlan) that VMs can attach to via their `bridgeName`.
    bcl.vlan.interface = cfg.interface;
  })
  ];
}
