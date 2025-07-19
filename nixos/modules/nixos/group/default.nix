{ config, lib, ... }:

let
  cfg = config.bcl.group;
in
{
  options.bcl.group = {
    name = lib.mkOption {
      type = lib.types.str;
      default = "";
    };
    role = lib.mkOption {
      type = lib.types.str;
      default = "";
    };
    secretFile = lib.mkOption { type = lib.types.path;};
  };

  config = lib.mkIf (cfg.name != "") {
    bcl.role.name = cfg.role;
  };
}
