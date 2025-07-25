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
    secretFile = lib.mkOption { type = lib.types.path;};
  };
}
