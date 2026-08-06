{ config, lib, ... }:
let
  cfg = config.bcl.data;

  singleSource = dataCfg:
    dataCfg.sourceFoldersPattern == null && builtins.length dataCfg.sourceFolders == 1;

  # bcl.disks mount points that could be matched by the given glob pattern,
  # i.e. whose path starts with the pattern's literal (non-glob) prefix.
  # E.g. for "/disks/*/Audio", the literal prefix is "/disks/", so any disk
  # mounted under /disks is a candidate. For "/disks/year*", the literal
  # prefix is "/disks/year", so only disks like /disks/year29 match - NOT
  # /disks/week1 (must be a literal string prefix, not just same parent dir,
  # otherwise e.g. "/disks/week*" and "/disks/year*" would both match every
  # disk under /disks).
  diskPathsForPattern = pattern:
    let
      prefixPath = builtins.head (lib.splitString "*" pattern);
    in
    lib.pipe config.bcl.disks [
      (lib.filterAttrs (_: diskCfg: lib.hasPrefix prefixPath diskCfg.path))
      (lib.mapAttrsToList (_: diskCfg: diskCfg.path))
    ];

  branchMode = dataCfg: if dataCfg.mode == "rw" then "RW" else "RO";

  # mergerfs branch spec: each path (or glob pattern) suffixed with its mode,
  # joined with ':'. mergerfs expands glob patterns itself at mount time.
  branches = dataCfg:
    lib.concatStringsSep ":" (
      (map (p: "${p}=${branchMode dataCfg}") dataCfg.sourceFolders)
      ++ lib.optional (dataCfg.sourceFoldersPattern != null) "${dataCfg.sourceFoldersPattern}=${branchMode dataCfg}"
    );

  # Paths this data mount must wait for. `depends` becomes
  # x-systemd.requires-mounts-for on the fileSystems entry, which systemd
  # translates to RequiresMountsFor= (i.e. both Requires= and After= on the
  # underlying disk's mount unit). This means a disk that fails to mount will
  # also make this data mount fail to start, rather than silently coming up
  # incomplete. Explicit sourceFolders resolve to their own disk path; a glob
  # pattern depends on every disk whose mount point could match it.
  dependsFor = dataCfg:
    lib.unique (dataCfg.sourceFolders ++ lib.optionals (dataCfg.sourceFoldersPattern != null) (diskPathsForPattern dataCfg.sourceFoldersPattern));

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
        # refuse to mount if a branch isn't an actual mountpoint (e.g. missing disk)
        "branches-mount-timeout-fail=true"
        "nofail" # not understood by mount command, but required by systemd to not fail the boot if a disk is missing
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
