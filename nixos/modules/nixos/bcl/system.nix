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
    id = lib.mkOption {
      type = lib.types.submodule {
        options = {
          motherboardUuid = lib.mkOption {
            type = lib.types.str;
            default = "";
          };
          cpuSerial = lib.mkOption {
            type = lib.types.str;
            default = "";
          };
          networkMacs = lib.mkOption {
            type = with lib.types; listOf str;
            default = [ ];
          };
          networkIps = lib.mkOption {
            type = with lib.types; listOf str;
            default = [ ];
          };
          disks = lib.mkOption {
            type = with lib.types; listOf str;
            default = [ ];
          };
        };
      };
      default = { };
    };
    hardware = lib.mkOption {
      type = lib.types.str;
      default = "";
    };
    sopsFile = lib.mkOption {
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


  config = lib.mkIf cfg.enable {
    bcl.users.syncthing = lib.mkIf (cfg.sopsFile != null) (
      lib.mapAttrs (_: _: {
        sopsFile = lib.mkDefault cfg.sopsFile;
      }) config.bcl.users.users
    );

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
      diskSystem = {
        enable = true;
        devices = cfg.devices;
      };
    };
  };
}


