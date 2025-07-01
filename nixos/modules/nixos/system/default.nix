{
  config,
  lib,
  pkgs,
  ...
}:
with lib.bcl;
let
  cfg = config.bcl.system;
in {
  options.bcl.system = {
    enable = lib.mkEnableOption "Enable the default settings?";
    ids = lib.mkOption {
      type = lib.types.str;
    };
    devices = lib.mkOption {
      type = with lib.types; listOf str;
      default = [ ];
    };
    hardware = lib.mkOption {
      type = lib.types.str;
      default = "";
    };
    role = lib.mkOption {
      type = lib.types.str;
      default = "";
    };
  };

  ###################

  config = lib.mkIf cfg.enable {
    environment.etc."ids.env".text = cfg.ids;
  };
}


