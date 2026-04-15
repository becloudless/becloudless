{ config, lib, ... }:

{
  options.bcl.hardware = {
    device = lib.mkOption {
      type = lib.types.str;
      default = "";
    };
    commons = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
    };
  };
}
