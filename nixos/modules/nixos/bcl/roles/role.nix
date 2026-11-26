{ config, lib, pkgs, inputs, ... }:
let
  cfg = config.bcl.role;
  revision = let self = inputs.self; in self.shortRev or self.dirtyShortRev or self.lastModified or "unknown";
  localeMap = {
    en = "en_US.UTF-8";
    fr = "fr_FR.UTF-8";
  };
  locale = localeMap.${cfg.language} or cfg.language;
in {

  options.bcl.role = {
    name = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = "Role name. Must match one of the registered knownRoles.";
    };
    knownRoles = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = "List of valid role names. Each role module registers itself here.";
    };
    setAdminPassword = lib.mkEnableOption "Add the password to the user";
    secretFile = lib.mkOption { type = lib.types.path;};
    language = lib.mkOption {
      type = lib.types.str;
      default = "en";
      description = "Language for the role (e.g. 'en', 'fr').";
    };
    keyboard = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "us" ];
      description = "Keyboard layouts for the role (e.g. [ 'us' ] or [ 'fr' 'us' ]). First layout will be used as default.";
    };
  };

  config = lib.mkIf (cfg.name != "") {
    assertions = [
      {
        assertion = builtins.elem cfg.name cfg.knownRoles;
        message = ''
          bcl.role.name is set to "${cfg.name}" which is not a known role.
          Known roles: ${lib.concatStringsSep ", " cfg.knownRoles}
          Make sure the corresponding role module is imported.
        '';
      }
    ];
    system.nixos.versionSuffix = "-${builtins.substring 0 8 (toString inputs.self.lastModifiedDate)}.${toString revision}";
    # system.nixos.label =

    environment.etc."nixos/current".source = inputs.self.outPath;

    services.xserver.xkb.layout = lib.concatStringsSep "," cfg.keyboard;
    console.keyMap = builtins.head cfg.keyboard;
    i18n.defaultLocale = locale;
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

    system.stateVersion = "23.11"; # never touch that
  };
}
