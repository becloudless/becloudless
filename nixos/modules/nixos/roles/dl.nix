{ config, lib, pkgs, ... }:

{
  config = lib.mkIf (config.bcl.role.name == "dl") {
    security.sudo.wheelNeedsPassword = false;
    bcl.role.setN0radPassword = true;

    programs.firefox = {
      enable = true;
    };

    environment.systemPackages = with pkgs; [
      vim
      wget
      wineWowPackages.stable
      winetricks
      mono
      wireguard-tools
    ];

    services.xserver.displayManager.gdm.enable = true;
    services.xserver.desktopManager.gnome.enable = true;
    services.xserver = {
      enable = true;
      xkb.layout = "us";
    };


    networking.firewall.enable = false;

    sops.secrets."wg.dl1.private" = {
      sopsFile = ./dl.secrets.yaml;
    };

    networking.wireguard = {
      enable = true;
      interfaces = {
        wg0 = {
          ips = [ "10.0.0.6" ];
          privateKeyFile = config.sops.secrets."wg.dl1.private".path;
#          postSetup = ''printf "nameserver 8.8.8.8" | ${pkgs.openresolv}/bin/resolvconf -a wg0 -m 0'';
#          postShutdown = "${pkgs.openresolv}/bin/resolvconf -d wg0";
          peers = [
            {
              publicKey = "fudeC2dCCuY52DSi/7YfMBKleR7x68/08xPUW8HJlXo=";
              allowedIPs = [ "0.0.0.0/0" ];
              endpoint = "pop.bcl.io:65530";
              persistentKeepalive = 25;
            }
          ];
        };
      };
    };
  };
}
