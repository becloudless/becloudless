{ config, lib, pkgs, options, ... }:
let
  cfg = config.bcl.role;
  isInstall = cfg.name == "install";
  # install iso need to be built with `--impure` to include the ssh host key in the image
  sshHostKeyFileEnv = builtins.getEnv "BCL_INSTALL_SSH_HOST_KEY_FILE";
in {
  config = lib.mkMerge [
    { bcl.role.knownRoles = [ "install" ]; }
    (lib.mkIf isInstall (
    {
      bcl.wifi.enable = true;
      environment.systemPackages = with pkgs; [
        nixos-facter
      ];

      # Workaround https://github.com/nix-community/nixos-anywhere/issues/613, adding keys to root user
      users.users.root.openssh.authorizedKeys.keys =
          lib.attrValues (lib.mapAttrs (_name: userCfg: userCfg.sshPublicKey)
            config.bcl.global.admins);


      # Define the nixos user for the install image
      # (for iso this is provided by installation-cd-minimal.nix, but raw-efi needs it explicitly)
      users.users.nixos = {
        isNormalUser = true;
        group = "nixos";
        openssh.authorizedKeys.keys =
          lib.attrValues (lib.mapAttrs (_name: userCfg: userCfg.sshPublicKey)
            config.bcl.global.admins);
      };
      users.groups.nixos = {};

      # give time to dhcp to get IP, so it will be display
      services.getty.extraArgs = [ "--delay=10" ];
      environment.etc."issue.d/ip.issue".text = "\\4\n";
      networking.dhcpcd.runHook = "${pkgs.utillinux}/bin/agetty --reload";
    }
    // lib.optionalAttrs (sshHostKeyFileEnv != "") {
      environment.etc."ssh/ssh_host_ed25519_key" = {
        mode = "0600";
        source = "${/. + sshHostKeyFileEnv}";
      };
      services.openssh.hostKeys = lib.mkForce [
        {
          path = "/etc/ssh/ssh_host_ed25519_key";
          type = "ed25519";
        }
      ];
    }
    // lib.optionalAttrs (options ? image && options.image ? baseName) {
#      image.baseName = lib.mkForce "bcl";
#      isoImage.squashfsCompression = "gzip -Xcompression-level 1";
#      isoImage.volumeID = lib.mkForce "bcl-iso";

#    "${nixpkgs}/nixos/modules/installer/cd-dvd/installation-cd-minimal.nix"
##            "${nixpkgs}/nixos/modules/installer/cd-dvd/channel.nix"
    }
  ))
  ];
}
