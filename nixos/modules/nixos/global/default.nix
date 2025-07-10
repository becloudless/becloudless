{config, lib, ...}:
let
  cfg = config.bcl.global;
in {
  options.bcl.global = {
    enable = lib.mkEnableOption "Enable the default settings?";
    networking.domain = lib.mkOption {
      type = lib.types.str;
    };
    time.timeZone = lib.mkOption {
      type = lib.types.str;
      default = "Europe/Paris";
    };
    i18n.defaultLocale = lib.mkOption {
      type = lib.types.str;
      default = "en_US.UTF-8";
    };

#    publicDomain = lib.mkOption {
#
#    };
#    users = lib.mkOption {
#      # one admin is mandatory
#
#      # global Admin
#      # keyboard layout
#      # public key
#      # password
#    };
#    networkRange = lib.mkOption {
#
#    };
#    networkWifi = lib.mkOption {
#      # name
#      # secret key
#    };
#    defaultLanguage = lib.mkOption {
#
#    };
#    defaultKeyboardLayout = lib.mkOption {
#
#    };

  };

  ###################

  config = lib.mkIf cfg.enable {
    networking.domain = cfg.networking.domain;
    time.timeZone = cfg.time.timeZone;
    i18n.defaultLocale = cfg.i18n.defaultLocale;
  };
}