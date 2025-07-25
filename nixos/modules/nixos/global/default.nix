{config, lib, ...}:
let
  cfg = config.bcl.global;
in {
  options.bcl.global = {
    enable = lib.mkEnableOption "Enable the default settings?";
    timeZone = lib.mkOption {
      type = lib.types.str;
      default = "Europe/Paris";
    };
    locale = lib.mkOption {
      type = lib.types.str;
      default = "en_US.UTF-8";
    };
    adminUser.login = lib.mkOption {
      type = lib.types.str;
    };
    adminUser.passwordSecretFile = lib.mkOption {
      type = lib.types.path;
    };
    adminUser.sshPublicKey = lib.mkOption {
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
#    defaultLanguage = lib.mkOption {
#
#    };
#    defaultKeyboardLayout = lib.mkOption {
#
#    };

  };

  ###################

  config = lib.mkIf cfg.enable {
    time.timeZone = cfg.timeZone;
    i18n.defaultLocale = cfg.locale;

    users.users."${cfg.adminUser.login}" = {
      isNormalUser = true;
      group = "users";
      extraGroups = [ "wheel" ];
      hashedPasswordFile = lib.mkIf config.bcl.role.setAdminPassword config.sops.secrets."adminPassword".path;
      openssh.authorizedKeys.keys = [
        cfg.adminUser.sshPublicKey
      ];
    };

   sops.secrets."adminPassword" = lib.mkIf config.bcl.role.setAdminPassword {
      neededForUsers = true;  # sops hook in the init process before creation of users
      sopsFile = cfg.adminUser.passwordSecretFile;
    };
  };
}