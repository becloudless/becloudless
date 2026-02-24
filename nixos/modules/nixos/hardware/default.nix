{ config, lib, ... }:

{
  options.bcl.hardware = {
    device = lib.mkOption {
      type = lib.types.str;
      default = "";
    };
  };
}
