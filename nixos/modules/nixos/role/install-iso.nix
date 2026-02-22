# This file replicates the essential config from nixpkgs'
# installation-cd-minimal.nix / installation-cd-base.nix.
#
# We cannot simply import those files because `imports` in NixOS modules is
# resolved before `config` is available, making any config-dependent conditional
# import cause infinite recursion. Instead we inline the relevant settings here,
# guarded by an options existence check so they are only applied in nixos-generators
# format evaluation contexts (where isoImage options exist), and never for regular
# nixosSystem builds.

{ config, lib, options, ... }:
let
  isInstall = config.bcl.role.name == "install";
  hasIsoImage = options ? isoImage && options.isoImage ? makeBootable;
in {
  config = lib.mkIf isInstall (
    {
      # Passwordless sudo for nixos user (installation-cd-base.nix)
      security.sudo.wheelNeedsPassword = lib.mkImageMediaOverride false;

      # nixos user for the install image (installation-cd-base.nix)
      users.users.nixos = {
        isNormalUser = true;
        group = "nixos";
        extraGroups = [ "wheel" "networkmanager" ];
      };
      users.groups.nixos = {};

      # Auto-login as nixos on tty1 (installation-cd-base.nix)
      services.getty.autologinUser = lib.mkImageMediaOverride "nixos";

      # Enable SSH (installation-cd-base.nix)
      services.openssh = {
        enable = true;
        settings.PermitRootLogin = lib.mkImageMediaOverride "yes";
      };
    }
    // lib.optionalAttrs hasIsoImage {
      # ISO image boot infrastructure (installation-cd-base.nix)
      isoImage.makeBootable = true;
      isoImage.makeEfiBootable = true;
      isoImage.squashfsCompression = "gzip -Xcompression-level 1";

      # Live system: keep everything in RAM (installation-cd-base.nix)
      boot.kernelParams = [ "copytoram" ];

      # Disable grub/systemd-boot — the ISO uses its own bootloader (installation-cd-base.nix)
      boot.loader.grub.enable = lib.mkImageMediaOverride false;
      boot.loader.systemd-boot.enable = lib.mkImageMediaOverride false;
      boot.loader.efi.canTouchEfiVariables = lib.mkImageMediaOverride false;
    }
  );
}
