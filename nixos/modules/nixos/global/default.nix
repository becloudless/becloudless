{config, lib, ...}:
let
  cfg = config.bcl.global;
in {
  options.bcl.global = {
    enable = lib.mkEnableOption "Enable the default settings?";
    timeZone = lib.mkOption { type = lib.types.str; default = "Europe/Paris"; };
    locale = lib.mkOption { type = lib.types.str; default = "en_US.UTF-8"; };
    domain = lib.mkOption { type = lib.types.str; description = "Domain name of the infrastructure."; };
    admin = lib.mkOption {
      type = lib.types.nullOr (lib.types.submodule ({ ... }: {
        options = {
          passwordSecretFile = lib.mkOption {
            type = lib.types.nullOr lib.types.path;
            default = null;
            description = "SOPS file containing the shared password for all admin users.";
          };
          users = lib.mkOption {
            type = lib.types.attrsOf (lib.types.submodule ({ name, ... }: {
              options = {
                sshPublicKey = lib.mkOption {
                  type = lib.types.nullOr lib.types.str;
                  default = null;
                  description = "SSH public key for admin user ${name}.";
                };
                extraGroups = lib.mkOption {
                  type = lib.types.listOf lib.types.str;
                  default = [ "wheel" ];
                  description = "Additional groups for admin user ${name}.";
                };
              };
            }));
            default = {};
            description = "Attribute set of admin users keyed by username.";
          };
        };
      }));
      default = null;
      description = "Definition of multiple admin users.";
    };
  };

  ###################

  config = lib.mkIf cfg.enable (
    let
      setAdminPasswordFlag = (config.bcl.role or { setAdminPassword = false; }).setAdminPassword;
      adminPasswordFile = if cfg.admin != null && cfg.admin.passwordSecretFile != null then cfg.admin.passwordSecretFile else null;
      admins = lib.optionalAttrs (cfg.admin != null) (lib.mapAttrs (name: userCfg: (
        let pk = userCfg.sshPublicKey; in {
          isNormalUser = true;
          group = "users";
          extraGroups = userCfg.extraGroups;
          openssh.authorizedKeys.keys = lib.mkIf (pk != null) [ pk ];
        } // lib.optionalAttrs setAdminPasswordFlag {
          hashedPasswordFile = config.sops.secrets.adminPassword.path;
        }
      )) cfg.admin.users);
    in {
      time.timeZone = cfg.timeZone;
      i18n.defaultLocale = cfg.locale;
      users.users = admins;
      sops.secrets.adminPassword = lib.mkIf (setAdminPasswordFlag && adminPasswordFile != null) {
        neededForUsers = true;
        sopsFile = adminPasswordFile;
      };
    }
  );
}