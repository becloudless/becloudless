{ config, lib, pkgs, inputs, ... }:
let
  srvNumber = lib.strings.toInt(builtins.substring ((builtins.stringLength config.networking.hostName) -1)  (-1) config.networking.hostName);
  cfg = config.bcl.role.serverProxmox;
in
{
  options.bcl.role.serverProxmox = {
    clusterNumber = lib.mkOption {type = lib.types.int; default = 1;};
  };

  ####################

  config = lib.mkMerge [
    { bcl.role.knownRoles = [ "serverProxmox" ]; }
    (lib.mkIf (config.bcl.role.name == "serverProxmox") {

    # Scoped to only hosts using this role, so it doesn't affect pkgs for any
    # other host or system (unlike adding it to the flake's global overlays).
    nixpkgs.overlays = [
      (final: prev: (inputs.proxmox-nixos.overlays.${prev.stdenv.hostPlatform.system} or (_: _: {})) final prev)
    ];

    bcl.diskSystem.encrypted = true;
    bcl.boot.ssh = true; # give password for disk encryption on boot

    bcl.role.setAdminPassword = true; # being able to log in to console
    security.sudo.wheelNeedsPassword = false;

    environment.systemPackages = with pkgs; [
      k9s
      ssh-to-age
      mergerfs
    ];

    networking.nameservers = ["192.168.40.12"];
    services.resolved.dnssec = "true";
    networking.firewall.enable = false;

    systemd.network.enable = true;
    systemd.network.networks.net = {
      matchConfig = {
        Name = "en* eth*";
      };
      networkConfig = {
        IgnoreCarrierLoss = true;
        Bridge = "vmbr0";
      };
    };
    systemd.network.netdevs.vmbr0.netdevConfig = {
      Kind = "bridge";
      Name = "vmbr0";
    };
    systemd.network.networks.vmbr0 = {
      matchConfig = {
        Name = "vmbr0";
      };
      networkConfig = {
        IgnoreCarrierLoss = true;
        KeepConfiguration = true;
      };
      address = [
        "192.168.41.${toString cfg.clusterNumber}${toString srvNumber}/22"
      ];
      routes = [
        {
          Gateway = "192.168.40.10";
          GatewayOnLink = true;
        }
      ];
    };

    services.proxmox-ve = {
      enable = true;
      ipAddress = "192.168.41.${toString cfg.clusterNumber}${toString srvNumber}";
      bridges = [ "vmbr0" ];
    };

    environment.persistence."/nix" = {
      hideMounts = true;
      directories = [
        { directory = "/var/lib/pve-cluster"; mode = "u=rwx,g=,o="; }
      ];
    };
  })
  ];
}
