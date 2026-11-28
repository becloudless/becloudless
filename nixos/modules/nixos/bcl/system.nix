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
    enable = lib.mkOption {
      type = lib.types.bool;
      # the install image has a role but no disk, no hardware: it is not a machine of the infrastructure. A machine of a group is on
      # without looking at the role: the role is set by its group module, which reads `bcl.group.name`
      default = cfg.group != "" || (config.bcl.role.name != "" && config.bcl.role.name != "install");
      defaultText = lib.literalExpression ''group != "" || (config.bcl.role.name != "" && config.bcl.role.name != "install")'';
      description = "Enable the bcl stack on the machine (boot, disks, hardware, /etc/bcl/config.yaml, upgrades with the bcl CLI). On with a role, or a group.";
    };
    id = lib.mkOption {
      description = "Optional identity of the machine. `bcl nixos install` uses it to find the system of a target when `--system` is not given, and warns when it does not match the target of `--system`.";
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
      description = "Optional group of the machine (see `bcl.group`), set by the group module that shares the role and the secrets of several machines.";
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


  config = lib.mkMerge [
    # outside of the gate: the group modules (that set the role) read it, the gate reads the role
    { bcl.group.name = cfg.group; }
    (lib.mkIf cfg.enable {
    bcl.users.syncthing = lib.mkIf (cfg.sopsFile != null) (
      lib.mapAttrs (_: _: {
        sopsFile = lib.mkDefault cfg.sopsFile;
      }) config.bcl.users.users
    );

    environment.etc."bcl/config.yaml".source =
      (pkgs.formats.yaml { }).generate "bcl-config.yaml" {
        repository = cfg.repository;
        disks = lib.mapAttrs (_: diskCfg:
          map (d: { path = d.path; location = d.location; }) diskCfg.devices
        ) config.bcl.disks;
      };

    bcl = {
      global = {
        enable = true;
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
    })
  ];
}


