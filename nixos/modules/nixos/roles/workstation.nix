{ config, lib, pkgs, ... }:

{
  config = lib.mkIf (config.bcl.role.name == "workstation") {
    bcl.disk.encrypted = true;
    bcl.boot.plymouth = true;
    bcl.boot.quiet = true;
    bcl.sound.enable = true;
    bcl.wifi.enable = true;
    bcl.role.setAdminPassword = true;
    bcl.wm = {
      name = "gnome";
      user = "kwiskas";
    };
    bcl.user = {
      enable = true;
      name = "kwiskas";
    };
    programs.firefox = {
      enable = true;
    };

    environment.systemPackages = with pkgs; [
      libreoffice
    ];

    services.xserver = {
      enable = true;
      xkb.layout = "fr,us";
    };

    console.keyMap = "us";
    i18n.defaultLocale = lib.mkForce "fr_FR.UTF-8";

    i18n.extraLocaleSettings = {
      LC_ADDRESS = "fr_FR.UTF-8";
      LC_IDENTIFICATION = "fr_FR.UTF-8";
      LC_MEASUREMENT = "fr_FR.UTF-8";
      LC_MONETARY = "fr_FR.UTF-8";
      LC_NAME = "fr_FR.UTF-8";
      LC_NUMERIC = "fr_FR.UTF-8";
      LC_PAPER = "fr_FR.UTF-8";
      LC_TELEPHONE = "fr_FR.UTF-8";
      LC_TIME = "fr_FR.UTF-8";
    };

#    sops.secrets."users.kwiskas.password" = {
#      neededForUsers = true;
#      sopsFile = ./hideki.secrets.yaml;
#    };



  };
}
