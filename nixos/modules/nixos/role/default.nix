{ config, lib, pkgs, inputs, ... }:
let
  cfg = config.bcl.role;
  revision = let self = inputs.self; in self.shortRev or self.dirtyShortRev or self.lastModified or "unknown";
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

    system.stateVersion = "23.11"; # never touch that
  };
}
