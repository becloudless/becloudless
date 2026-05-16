{ config, lib, pkgs, ... }:
let
  cfg = config.bcl.data;

  # Convert a mount path to its systemd unit name, e.g. /data/Videos -> data-Videos.mount
  mountUnitName = path:
    (builtins.replaceStrings [ "/" ] [ "-" ] (lib.removePrefix "/" path)) + ".mount";

  singleSource = dataCfg:
    dataCfg.sourceFoldersPattern == null && builtins.length dataCfg.sourceFolders == 1;

  usesMergerfs = dataCfg:
    dataCfg.sourceFoldersPattern != null || builtins.length dataCfg.sourceFolders > 1;

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
        # most shared path, most free space
        # try to keep files to the same disk. Filling biggest disks space first
        "category.create=mspmfs"
        # most free space
        # pick next biggest space
        "moveonenospc=mfs"
        "minfreespace=10G"
        "nofail"
      ];
    };
  }) cfg;

  multiSourceCfg = lib.filterAttrs (_: dataCfg: usesMergerfs dataCfg) cfg;

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
      script =
        let
          branchMode = if dataCfg.mode == "rw" then "RW" else "RO";
          addBranch = ''
            add_branch() {
              local src="$1"
              if [ -d "$src" ]; then
                echo "Adding $src to mergerfs at ${dataCfg.path}"
                setfattr -n user.mergerfs.branches \
                  -v "+>$src=${branchMode}" \
                  "${dataCfg.path}/.mergerfs"
              else
                echo "Skipping $src (not found)"
              fi
            }
          '';
          staticPart = lib.optionalString (dataCfg.sourceFolders != []) ''
            for src in ${lib.concatStringsSep " " dataCfg.sourceFolders}; do
              add_branch "$src"
            done
          '';
          patternPart = lib.optionalString (dataCfg.sourceFoldersPattern != null) ''
            for src in ${dataCfg.sourceFoldersPattern}; do
              add_branch "$src"
            done
          '';
        in addBranch + staticPart + patternPart;
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
          default     = [];
          apply       = s: if builtins.isString s then [ s ] else s;
          description = "Source folder(s) to merge. A single string is accepted for the single-source case.";
        };
        sourceFoldersPattern = lib.mkOption {
          type        = lib.types.nullOr lib.types.str;
          default     = null;
          description = "Shell glob pattern evaluated at runtime to discover source folders (e.g. \"/disks/*/Videos\"). Always uses mergerfs + systemd service.";
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
    assertions = lib.mapAttrsToList (name: dataCfg: {
      assertion = dataCfg.sourceFolders != [] || dataCfg.sourceFoldersPattern != null;
      message   = "bcl.data.${name}: at least one of sourceFolders or sourceFoldersPattern must be set.";
    }) cfg;
    fileSystems      = fileSystemsEntries;
    systemd.services = dataSourceServices;
  };
}
