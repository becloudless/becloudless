{ config, lib, pkgs, ... }:

{
  config = lib.mkIf (config.bcl.role.name == "laptop") {
#    bcl.disk.encrypted = true; # TODO this cannot work on one device
    bcl.boot.plymouth = true;
    bcl.boot.quiet = true;
    bcl.role.setN0radPassword = true;
    bcl.sound.enable = true;
    bcl.wifi.enable = true;
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

    sops.secrets."users.kwiskas.password" = {
      neededForUsers = true;
      sopsFile = ./hideki.secrets.yaml;
    };



  };
}
