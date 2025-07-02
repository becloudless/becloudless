{ config, lib, ... }:

{

  options.bcl.hardware = {
    device = lib.mkOption { # TODO check device matches one import or it will be silently ignored
      type = lib.types.str;
      default = "";
    };
    common = lib.mkOption { # TODO check
      type = lib.types.str;
      default = "";
    };
  };

}
