{ config, lib, pkgs, options, ... }:
let
  isInstall = config.bcl.role.name == "install";
  hasImageBaseName = options ? image && options.image ? baseName;
in {
  config = lib.mkMerge [
    (lib.mkIf isInstall {
      bcl.wifi.enable = true;
      environment.systemPackages = with pkgs; [
        nixos-facter
      ];

      # Add admin SSH keys to the nixos user created by install-iso.nix
      users.users.nixos.openssh.authorizedKeys.keys =
        lib.attrValues (lib.mapAttrs (_name: userCfg: userCfg.sshPublicKey)
          config.bcl.global.admins);

      # This is impure: include ssh host key in the iso without storing it in git.
      # It still lives in the store, but there is not much secret behind this private key.
      environment.etc."ssh/ssh_host_ed25519_key" = {
        mode = "0600";
        source = "${/tmp/install-ssh_host_ed25519_key}";
      };
      services.openssh.hostKeys = lib.mkForce [
        {
          path = "/etc/ssh/ssh_host_ed25519_key";
          type = "ed25519";
        }
      ];

      # Give time to dhcp to get IP, so it will be displayed
      services.getty.extraArgs = [ "--delay=10" ];
      environment.etc."issue.d/ip.issue".text = "\\4\n";
      networking.dhcpcd.runHook = "${pkgs.utillinux}/bin/agetty --reload";
    })

    (lib.mkIf isInstall (lib.optionalAttrs hasImageBaseName {
      image.baseName = lib.mkForce "bcl";
      isoImage.volumeID = lib.mkForce "bcl-iso";
    }))
  ];
}
