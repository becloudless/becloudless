{ config, lib, pkgs, ... }:

let
  vmUsers = lib.filterAttrs (_: u: u.enable) config.bcl.users.virtManager;
in
{
  options.bcl.users.virtManager = lib.mkOption {
    type = lib.types.attrsOf (lib.types.submodule {
      options = {
        enable = lib.mkEnableOption "Enable virt-manager for this user";
      };
    });
    default = {};
    description = "virt-manager per-user configuration, keyed by username.";
  };

    # virtualisation.libvirtd = {
    #   enable = true;
    #   qemu = {
    #     package = pkgs.qemu_kvm;
    #     runAsRoot = true;
    #     swtpm.enable = true;
    #   };
    # };

  config = lib.mkIf (vmUsers != {}) {
    virtualisation.libvirtd.enable = true;

    users.groups.libvirtd.members = lib.attrNames vmUsers;

    environment.systemPackages = with pkgs; [
      virt-manager
      virtiofsd
    ];

    home-manager.users = lib.mapAttrs (_: _: { lib, ... }: {
      dconf.settings = with lib.hm.gvariant; {
        "org/virt-manager/virt-manager" = {
          xmleditor-enabled = true;
        };

        "org/virt-manager/virt-manager/confirm" = {
          forcepoweroff = false;
        };
      };
    }) vmUsers;
  };
}
