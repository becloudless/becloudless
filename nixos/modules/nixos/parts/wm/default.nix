{ config, lib, ... }: let
  cfg = config.bcl.wm;
in {
  options.bcl.wm = {
    name = lib.mkOption {
      type = lib.types.str;
      default = "";
    };
  };
}
