{ config, lib, pkgs, ... }: {

    bcl.wifi.enable = true;

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

    services.getty.autologinUser = lib.mkForce "n0rad";
    services.getty.helpLine = lib.mkForce ">> Run bcl-install to install";

    # give time to dhcp to get IP, so it will be display
    services.getty.extraArgs = [ "--delay=5" ];
    environment.etc."issue.d/ip.issue".text = "\\4\n";
    networking.dhcpcd.runHook = "${pkgs.utillinux}/bin/agetty --reload";




}