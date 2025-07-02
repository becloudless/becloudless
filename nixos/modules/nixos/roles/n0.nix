{ config, lib, inputs, pkgs, ... }: {

  config = lib.mkIf (config.bcl.role.name == "n0") {
    bcl.disk.encrypted = true;
    bcl.role.setN0radPassword = true;
    bcl.wm = {
      name = "gnome";
      user = "n0rad";
    };
    bcl.bluetooth.enable = true;
    bcl.docker.enable = true;
    bcl.printScan.enable = true;
    bcl.sound.enable = true;
    bcl.virtualbox.enable = true;
    bcl.wifi.enable = true;

    services.xserver = {
      xkb.layout = "us";
    };

    home-manager.users.n0rad = { lib, pkgs, ... }: {
      imports = [ (inputs.impermanence + "/home-manager.nix") ];
    };

    # boot.crashDump.enable = true;


    networking.firewall = {
      allowedUDPPorts = [ 51820 ];
    };
    sops.secrets."wg.${config.networking.hostName}.private" = {
      owner = "n0rad";
      sopsFile = ./n0.secrets.yaml;
    };

  #  networking.wireguard.interfaces.wg0 = {
  #    ips = [ "192.168.39.11/24" ];
  #    listenPort = 51820;
  #    privateKeyFile = config.sops.secrets."wg.${config.networking.hostName}.private".path;
  #
  #    peers = [{
  #        publicKey = "8SLVoZQn6NAjDqbyVP0AN+f/nKyZwFQ8Ooi1+gm/axA=";
  #        # Forward all the traffic via VPN.
  #        allowedIPs = [ "192.168.39.0/24" ];
  #        # Or forward only particular subnets
  #        #allowedIPs = [ "10.100.0.1" "91.108.12.0/22" ];
  #
  #        # Set this to the server IP and port.
  #        endpoint = "wg.bcl.io:13233";
  #
  #        # Send keepalives every 25 seconds. Important to keep NAT tables alive.
  #        persistentKeepalive = 25;
  #    }];
  #  };


    # android
    programs.adb.enable = true;

    users.users.n0rad = {
      extraGroups = ["adbusers" "keyd" "docker"];
    };


    # put mouses/keyboards into deep sleep
    # powerManagement.powertop.enable = true;

    services.thermald.enable = true;
  #  services.tlp.enable = true;
    services.power-profiles-daemon.enable = true;
    services.acpid.enable = true;
    services.flatpak.enable = true;

    # sshfs prevent suspend
    powerManagement.powerDownCommands = ''
      ${pkgs.procps}/bin/pkill sshfs
    '';

    # system.userActivationScripts.script.text = ''
    #   #!/bin/bash
    #   dconf write /org/gnome/shell/extensions/azwallpaper/slideshow-slide-duration "(4, 0, 0)"
    # '';

  #  systemd.tmpfiles.rules = [
      # "L /var/lib/AccountsService/icons/n0rad - - - - /home/n0rad/Pictures/face"
      # "L /var/lib/AccountsService/users/n0rad - - - - /home/n0rad/.config/AccountService"
  #  ] ;

  };
}
