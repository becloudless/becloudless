{ config, lib, ... }:
let
  cfg = config.bcl.data;

  singleSource = dataCfg:
    dataCfg.sourceFoldersPattern == null && builtins.length dataCfg.sourceFolders == 1;

  # All bcl.disks mount points.
  allDiskPaths = lib.mapAttrsToList (_: diskCfg: diskCfg.path) config.bcl.disks;

  branchMode = dataCfg: if dataCfg.mode == "rw" then "RW" else "RO";

  # mergerfs branch spec: each path (or glob pattern) suffixed with its mode,
  # joined with ':'. mergerfs expands glob patterns itself at mount time.
  branches = dataCfg:
    lib.concatStringsSep ":" (
      (map (p: "${p}=${branchMode dataCfg}") dataCfg.sourceFolders)
      ++ lib.optional (dataCfg.sourceFoldersPattern != null) "${dataCfg.sourceFoldersPattern}=${branchMode dataCfg}"
    );

  # Paths this data mount must wait for. Explicit sourceFolders resolve to their
  # underlying bcl.disks mount via x-systemd.requires-mounts-for (see `depends`
  # option semantics: any filesystem whose mount point is a parent of the path
  # is ordered first). A glob pattern could match any disk, so depend on all of
  # them to make sure none are missed.
  dependsFor = dataCfg:
    lib.unique (dataCfg.sourceFolders ++ lib.optionals (dataCfg.sourceFoldersPattern != null) allDiskPaths);

  fileSystemsEntries = lib.mapAttrs' (name: dataCfg: {
    name  = dataCfg.path;
    value = if singleSource dataCfg then {
      device  = builtins.head dataCfg.sourceFolders;
      fsType  = "none";
      options = [ "bind" dataCfg.mode "defaults" "nofail" ];
      depends = dependsFor dataCfg;
    } else {
      device  = branches dataCfg;
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
        # move current write file that cannot fit to next biggest space disk
        "moveonenospc=mfs"
        "minfreespace=4G"
        "nofail"
      ];
      depends = dependsFor dataCfg;
    };
  }) cfg;

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
          description = "Shell glob pattern expanded by mergerfs itself at mount time to discover source folders (e.g. \"/disks/*/Videos\"). Always uses mergerfs.";
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
    fileSystems = fileSystemsEntries;
  };
}
