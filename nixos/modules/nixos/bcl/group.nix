{ config, lib, ... }:

let
  cfg = config.bcl.group;
in
{
  options.bcl.group = {
    name = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = "Group name. Must match one of the registered knownGroups.";
    };
    knownGroups = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = "List of valid group names. Each group module registers itself here.";
    };
    secretFile = lib.mkOption { type = lib.types.path;};
  };

  config = lib.mkIf (cfg.name != "") {
    assertions = [
      {
        assertion = builtins.elem cfg.name cfg.knownGroups;
        message = ''
          bcl.group.name is set to "${cfg.name}" which is not a known group.
          Known groups: ${lib.concatStringsSep ", " cfg.knownGroups}
          Make sure the corresponding group module is imported.
        '';
      }
    ];
    system.nixos.tags = ["group-${cfg.name}"];
  };

}
