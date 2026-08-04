{ config, lib, pkgs, ... }:
let
  cfg = config.bcl.data;

  # Resolve a sourceFoldersPattern (e.g. "/disks/*/Videos" or "/disks/week*")
  # into a static list of real folders, by matching the pattern's single '*'
  # wildcard against the mount paths declared in bcl.disks. The wildcard only
  # ever matches within one path segment (like a shell glob); anything after
  # the segment containing '*' is treated as a literal suffix appended to the
  # matching disk's path.
  resolvePattern = pattern:
    if pattern == null then [] else
    let
      m = builtins.match "(.*)\\*(.*)" pattern;
    in
    if m == null then
      throw "bcl.data: sourceFoldersPattern '${pattern}' must contain exactly one '*' wildcard."
    else
    let
      prefix   = builtins.elemAt m 0;
      rest     = builtins.elemAt m 1;
      rm       = builtins.match "([^/]*)(/.*)?" rest;
      restTail = builtins.elemAt rm 0;
      suffix   = let s = builtins.elemAt rm 1; in if s == null then "" else s;
      regex    = lib.escapeRegex prefix + "[^/]*" + lib.escapeRegex restTail;
      diskPaths = map (diskCfg: diskCfg.path) (lib.attrValues config.bcl.disks);
      matched  = builtins.filter (p: builtins.match regex p != null) diskPaths;
    in map (p: p + suffix) matched;

  resolvedSourceFolders = dataCfg:
    dataCfg.sourceFolders ++ (resolvePattern dataCfg.sourceFoldersPattern);

  singleSource = dataCfg:
    dataCfg.sourceFoldersPattern == null && builtins.length dataCfg.sourceFolders == 1;

  fileSystemsEntries = lib.mapAttrs' (name: dataCfg: {
    name  = dataCfg.path;
    value = if singleSource dataCfg then {
      device  = builtins.head dataCfg.sourceFolders;
      fsType  = "none";
      options = [ "bind" dataCfg.mode "defaults" "nofail" ];
    } else
      let
        branchMode = if dataCfg.mode == "rw" then "RW" else "RO";
        branches   = resolvedSourceFolders dataCfg;
      in {
        device  = lib.concatStringsSep ":" (map (src: "${src}=${branchMode}") branches);
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
          "nofail"
        ];
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
          description = "Glob-like pattern with a single '*' wildcard, statically resolved at build time against bcl.disks mount paths (e.g. \"/disks/*/Videos\"). Always uses mergerfs.";
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
