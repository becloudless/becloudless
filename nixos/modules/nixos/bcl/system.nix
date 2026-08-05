{
  config,
  lib,
  pkgs,
  ...
}:
with lib.bcl;
let
  cfg = config.bcl.system;
  globalRepository = config.bcl.global.git.repository or null;
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
    repository = lib.mkOption {
      type = lib.types.str;
      default = if globalRepository != null then globalRepository else "";
      description = ''
        Upstream infra git repository used by the bcl CLI (e.g. "bcl nixos upgrade")
        when no local git repository / --git flag is used. Written to
        /etc/bcl/config.yaml so it doesn't need to be passed on the command line.
        Defaults to bcl.global.git.repository.
      '';
    };
  };


  config = lib.mkIf cfg.enable {
    bcl.users.syncthing = lib.mkIf (cfg.sopsFile != null) (
      lib.mapAttrs (_: _: {
        sopsFile = lib.mkDefault cfg.sopsFile;
      }) config.bcl.users.users
    );

    environment.etc."bcl/config.yaml".source =
      (pkgs.formats.yaml { }).generate "bcl-config.yaml" {
        repository = cfg.repository;
        disks = lib.mapAttrs (_: diskCfg: {
          path = diskCfg.path;
          location = diskCfg.location;
        }) config.bcl.disks;
      };

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


