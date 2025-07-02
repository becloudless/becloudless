{ config, lib, ... }: let
  cfg = config.bcl.wm;
in {
  options.bcl.wm = {
    name = lib.mkOption { # TODO check it matches an import
      type = lib.types.str;
      default = "";
    };
    user = lib.mkOption {
      type = lib.types.str;
#      default = "";
    };
  };
}
