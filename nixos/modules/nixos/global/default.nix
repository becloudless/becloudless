{config, lib, ...}:
let
  cfg = config.bcl.global;
in {
  options.bcl.global = {
    enable = lib.mkEnableOption "Enable the default settings?";
    localDomain = lib.mkOption {
      type = lib.types.str;
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
#    timezone = lib.mkOption {
#
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
#    networking.domain = cfg.localDomain;
  };
}