{config, lib, ...}:
let
  cfg = config.bcl.global;
in {
  options.bcl.global = {
    enable = lib.mkEnableOption "Enable the default settings?";
    timeZone = lib.mkOption { type = lib.types.str; default = "Europe/Paris"; };
    locale = lib.mkOption { type = lib.types.str; default = "en_US.UTF-8"; };
    name = lib.mkOption { type = lib.types.str; description = "Name of the whole infrastructure, a-zA-Z-. usually the domain without the TLD"; };
    domain = lib.mkOption { type = lib.types.str; description = "Domain name of the infrastructure"; };
    git = lib.mkOption {
      type = lib.types.nullOr (lib.types.submodule ({ ... }: {
        options = {
          publicKey = lib.mkOption { type = lib.types.str; description = "Git repo public key"; };
        };
      }));
      default = null;
      description = "Definition of multiple admin users.";
    };
    admin = lib.mkOption {
      type = lib.types.nullOr (lib.types.submodule ({ ... }: {
        options = {
          passwordSecretFile = lib.mkOption {
            type = lib.types.nullOr lib.types.path;
            default = null;
            description = "SOPS file containing the password entries users.<name>.password for each admin user.";
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
      # Build user attribute set with optional hashedPasswordFile referencing per-user secret
      admins = lib.optionalAttrs (cfg.admin != null) (lib.mapAttrs (name: userCfg: (
        let pk = userCfg.sshPublicKey; in {
          isNormalUser = true;
          group = "users";
          extraGroups = userCfg.extraGroups;
          openssh.authorizedKeys.keys = lib.mkIf (pk != null) [ pk ];
        } // lib.optionalAttrs (setAdminPasswordFlag && adminPasswordFile != null) {
          hashedPasswordFile = config.sops.secrets."users.${name}.password".path;
        }
      )) cfg.admin.users);
      # Build secrets attrset for per-user passwords when enabled
      adminPasswordSecrets = lib.optionalAttrs (setAdminPasswordFlag && adminPasswordFile != null && cfg.admin != null) (
        lib.mapAttrs' (name: _: {
          name = "users.${name}.password"; # matches key in SOPS YAML file
          value = {
            neededForUsers = true;
            sopsFile = adminPasswordFile;
          };
        }) cfg.admin.users
      );
    in {
      time.timeZone = cfg.timeZone;
      i18n.defaultLocale = cfg.locale;
      users.users = admins;
      # Merge per-user secrets; no single shared adminPassword secret anymore
      sops.secrets = adminPasswordSecrets;
    }
  );
}