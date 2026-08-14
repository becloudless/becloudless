{ config, lib, pkgs, options, ... }:
let
  cfg = config.bcl.role;
  isInstall = cfg.name == "install";
in {
  options.bcl.role.install = {
    sshHostKeyFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = ''
        Path to a pre-generated ssh host ed25519 private key to bake into the
        install image. Reading this path requires `--impure` since it lives
        outside the flake. When left null (default), the build stays pure
        and sshd generates its own host key on first boot instead.
      '';
    };
  };

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
    // lib.optionalAttrs (cfg.install.sshHostKeyFile != null) {
      # this is impure to include a pre-generated ssh host key in the iso,
      # without having it in git. Still it lives in the store, but there is
      # not much secret behind this private key
      environment.etc."ssh/ssh_host_ed25519_key" = {
        mode = "0600";
        source = cfg.install.sshHostKeyFile;
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
