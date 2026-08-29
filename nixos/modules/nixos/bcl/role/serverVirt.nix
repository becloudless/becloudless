{ config, lib, pkgs, ... }:
let
  cfg = config.bcl.role.serverVirt;
in
{
  options.bcl.role.serverVirt = {
    # TODO remove and take it from networking range instead
    cidr = lib.mkOption { type = lib.types.str; example = "192.168.41.0/24"; };
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

    bcl.cluster.enable = true;

    services.resolved.dnssec = "true";
    networking.firewall.enable = false;
  })
  ];
}
