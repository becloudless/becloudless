{ config, lib, pkgs, ... }:

let
  cfg = config.bcl.role.workstation;

  localeMap = {
    en = "en_US.UTF-8";
    fr = "fr_FR.UTF-8";
  };

  locale = localeMap.${cfg.language} or "${cfg.language}";
in
{
  options.bcl.role.workstation = {
    language = lib.mkOption {
      type = lib.types.str;
      default = "en";
      description = "Language for the workstation (e.g. 'en', 'fr').";
    };
    keyboard = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "us" ];
      description = "Keyboard layouts for the workstation (e.g. [ 'us' ] or [ 'fr' 'us' ]). First layout will be used as default.";
    };
  };

  config = lib.mkIf (config.bcl.role.name == "workstation") {
    bcl.disk.encrypted = true;
    bcl.boot.plymouth = true;
    bcl.boot.quiet = true;
    bcl.sound.enable = true;
    bcl.wifi.enable = true;
    bcl.role.setAdminPassword = true;
    bcl.keepassxc.enable = true;

    programs.firefox = {
      enable = true;
    };

    environment.systemPackages = with pkgs; [
      libreoffice
      vscodium
      finamp
    ];

    services.xserver = {
      enable = true;
      xkb.layout = lib.concatStringsSep "," cfg.keyboard;
    };

    console.keyMap = builtins.head cfg.keyboard;
    i18n.defaultLocale = lib.mkForce locale;

    i18n.extraLocaleSettings = {
      LC_ADDRESS = locale;
      LC_IDENTIFICATION = locale;
      LC_MEASUREMENT = locale;
      LC_MONETARY = locale;
      LC_NAME = locale;
      LC_NUMERIC = locale;
      LC_PAPER = locale;
      LC_TELEPHONE = locale;
      LC_TIME = locale;
    };

  };
}
