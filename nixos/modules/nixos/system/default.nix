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
    role = lib.mkOption {
      type = lib.types.str;
      default = "";
    };
  };

  ###################

  imports = lib.filter
              (n: !lib.strings.hasSuffix "default.nix" n && lib.strings.hasSuffix ".nix" n)
              (lib.filesystem.listFilesRecursive ../.);

  config = lib.mkIf cfg.enable {
    environment.etc."ids.env".text = cfg.ids;
    bcl = {
      role = {
        enable = (cfg.role != "");
        name = cfg.role;
      };
      boot = {
        enable = true;
      };
      disk = {
        enable = true;
        devices = cfg.devices;
      };
    };
  };
}


