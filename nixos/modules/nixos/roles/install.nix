{ config, lib, pkgs, ... }:
{
  config = lib.mkIf (config.bcl.role.name == "install") {
    bcl.wifi.enable = true;
    environment.systemPackages = with pkgs; [
      nixos-facter
    ];

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

  };
}
