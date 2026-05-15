{ config, lib, pkgs, ... }:
let
  cfg = config.bcl.data;

  # Convert a mount path to its systemd unit name, e.g. /data/Videos -> data-Videos.mount
  mountUnitName = path:
    (builtins.replaceStrings [ "/" ] [ "-" ] (lib.removePrefix "/" path)) + ".mount";

  singleSource = dataCfg: builtins.length dataCfg.sourceFolders == 1;

  fileSystemsEntries = lib.mapAttrs' (name: dataCfg: {
    name  = dataCfg.path;
    value = if singleSource dataCfg then {
      device  = builtins.head dataCfg.sourceFolders;
      fsType  = "none";
      options = [ "bind" dataCfg.mode "defaults" "nofail" ];
    } else {
      device  = "/var/empty";
      fsType  = "fuse.mergerfs";
      options = [
        dataCfg.mode
        "defaults"
        "allow_other"
        "use_ino"
        "cache.files=partial"
        "dropcacheonclose=true"
        "category.create=msplfs"
        "minfreespace=50G"
        "nofail"
      ];
    };
  }) cfg;

  multiSourceCfg = lib.filterAttrs (_: dataCfg: !(singleSource dataCfg)) cfg;

  dataSourceServices = lib.mapAttrs' (name: dataCfg: {
    name = "data-sources-${name}";
    value = {
      description = "Add source folders to mergerfs mount ${dataCfg.path}";
      after    = [ "local-fs.target" (mountUnitName dataCfg.path) ];
      requires = [ (mountUnitName dataCfg.path) ];
      wantedBy = [ "multi-user.target" ];
      path = with pkgs; [ attr ];
      serviceConfig = {
        Type            = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        for src in ${lib.concatStringsSep " " dataCfg.sourceFolders}; do
          if [ -d "$src" ]; then
            echo "Adding $src to mergerfs at ${dataCfg.path}"
            setfattr -n user.mergerfs.branches \
              -v "+>$src=${if dataCfg.mode == "rw" then "RW" else "RO"}" \
              "${dataCfg.path}/.mergerfs"
          else
            echo "Skipping $src (not found)"
          fi
        done
      '';
    };
  }) multiSourceCfg;

in {
  options.bcl.data = lib.mkOption {
    default     = {};
    description = "Named mergerfs data mount configurations.";
    example     = {
      Videos = {
        sourceFolders = [ "/disks/hdd1/Videos" "/disks/hdd2/Videos" ];
      };
    };
    type = lib.types.attrsOf (lib.types.submodule ({ name, ... }: {
      options = {
        path = lib.mkOption {
          type        = lib.types.str;
          default     = "/data/${name}";
          description = "Mount point for the merged view. Defaults to /data/<name>.";
        };
        sourceFolders = lib.mkOption {
          type        = lib.types.either lib.types.str (lib.types.listOf lib.types.str);
          apply       = s: if builtins.isString s then [ s ] else s;
          description = "Source folder(s) to merge. A single string is accepted for the single-source case.";
        };
        mode = lib.mkOption {
          type        = lib.types.enum [ "rw" "ro" ];
          default     = "ro";
          description = "Mount mode: rw (read-write) or ro (read-only).";
        };
      };
    }));
  };

  config = lib.mkIf (cfg != {}) {
    fileSystems      = fileSystemsEntries;
    systemd.services = dataSourceServices;
  };
}
