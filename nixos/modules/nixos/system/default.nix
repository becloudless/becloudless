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
    hardware = lib.mkOption {
      type = lib.types.str;
      default = "";
    };
    secretFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
    };
    devices = lib.mkOption {
      type = with lib.types; listOf str;
      default = [ ];
    };
    group = lib.mkOption {
      type = lib.types.str;
      default = "";
    };
  };

  ###################

  # TODO move that somewhere else
  imports = lib.filter
              (n: !lib.strings.hasSuffix "default.nix" n && lib.strings.hasSuffix ".nix" n)
              (lib.filesystem.listFilesRecursive ../.);

  config = lib.mkIf cfg.enable {
    environment.etc."ids.env".text = cfg.ids;

    bcl.users.syncthing.sopsFile = lib.mkIf (cfg.secretFile != null) cfg.secretFile;

    bcl = {
      global = {
        enable = true;
      };
      group = {
        name = cfg.group;
      };
      boot = {
        enable = true;
      };
      hardware = {
        device = cfg.hardware;
      };
      disk = {
        enable = true;
        devices = cfg.devices;
      };
    };
  };
}


