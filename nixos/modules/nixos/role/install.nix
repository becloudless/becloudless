{ config, lib, pkgs, ... }:
{
  config = lib.mkIf (config.bcl.role.name == "install") {
    bcl.wifi.enable = true;
    environment.systemPackages = with pkgs; [
      nixos-facter
    ];

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

    # this is impure to include ssh host key to iso, without having it in git
    # still it lives in the store, but there is not much secrets behind this private key
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


    # give time to dhcp to get IP, so it will be display
    services.getty.extraArgs = [ "--delay=10" ];
    environment.etc."issue.d/ip.issue".text = "\\4\n";
    networking.dhcpcd.runHook = "${pkgs.utillinux}/bin/agetty --reload";

  };
}
