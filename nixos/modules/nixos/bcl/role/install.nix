{ config, lib, pkgs, options, ... }:
let
  cfg = config.bcl.role;
  isInstall = cfg.name == "install";
in {
  options.bcl.role.install = {
    enableSshHostKey = lib.mkEnableOption ''
      baking a pre-generated ssh host ed25519 private key into the install
      image. The key content is provided by the `bcl` cli at build time via
      the BCL_INSTALL_SSH_HOST_KEY_FILE environment variable, which requires
      building with --impure (handled automatically by `bcl nixos iso build`).
      When disabled (default), the build stays pure and sshd generates its
      own host key on first boot instead
    '';
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
    // lib.optionalAttrs cfg.install.enableSshHostKey (
      let
        # this is impure to include a pre-generated ssh host key in the iso,
        # without having it in git. Still it lives in the store, but there is
        # not much secret behind this private key
        keyFileEnv = builtins.getEnv "BCL_INSTALL_SSH_HOST_KEY_FILE";
        keyFile =
          if keyFileEnv == "" then
            throw "bcl.role.install.enableSshHostKey is true but BCL_INSTALL_SSH_HOST_KEY_FILE is not set (build via `bcl nixos iso build`)"
          else
            /. + keyFileEnv;
      in {
        environment.etc."ssh/ssh_host_ed25519_key" = {
          mode = "0600";
          source = "${keyFile}";
        };
        services.openssh.hostKeys = lib.mkForce [
          {
            path = "/etc/ssh/ssh_host_ed25519_key";
            type = "ed25519";
          }
        ];
      }
    )
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
