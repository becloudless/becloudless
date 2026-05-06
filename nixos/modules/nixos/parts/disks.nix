{ config, lib, ... }:
let
  cfg = config.bcl.disks;

  isRaid = diskCfg: builtins.length diskCfg.devices > 1;

  # Filesystem (or LUKS-wrapped filesystem) content leaf
  fsContent = name: diskCfg:
    if diskCfg.encrypted then {
      type    = "luks";
      name    = name;
      settings.allowDiscards = true;
      passwordFile = "/root/secret.key";
      content = {
        type       = "filesystem";
        format     = diskCfg.format;
        mountpoint = diskCfg.path;
      };
    } else {
      type       = "filesystem";
      format     = diskCfg.format;
      mountpoint = diskCfg.path;
    };

  # One disko disk entry per physical device
  mkDiskEntries = name: diskCfg:
    builtins.listToAttrs (lib.imap0 (i: device: {
      name  = "${name}_${toString i}";
      value = {
        type    = "disk";
        device  = device;
        content = {
          type       = "gpt";
          partitions.primary = {
            size    = "100%";
            content = if isRaid diskCfg then {
              type = "mdraid";
              name = name;
            } else fsContent name diskCfg;
          };
        };
      };
    }) diskCfg.devices);

  # One disko mdadm entry per RAID disk
  mkMdadmEntry = name: diskCfg: {
    type    = "mdadm";
    level   = diskCfg.raidMode;
    content = fsContent name diskCfg;
  };

  allDiskEntries =
    builtins.foldl' (acc: e: acc // e) {}
      (lib.mapAttrsToList mkDiskEntries cfg);

  raidConfigs  = lib.filterAttrs (_: diskCfg: isRaid diskCfg) cfg;
  mdadmEntries = lib.mapAttrs mkMdadmEntry raidConfigs;

in {
  options.bcl.disks = lib.mkOption {
    default     = {};
    description = "Named data-disk configurations managed by disko.";
    example     = {
      ssd1 = {
        path      = "/disks/ssd1";
        encrypted = true;
        format    = "btrfs";
        raidMode  = 0;             # default, used when devices > 1
        devices   = [ "/dev/disk/by-id/xxx" "/dev/disk/by-id/yyy" ];
      };
    };
    type = lib.types.attrsOf (lib.types.submodule ({ name, ... }: {
      options = {
        path = lib.mkOption {
          type        = lib.types.str;
          default     = "/disks/${name}";
          description = "Mount point for the assembled volume. Defaults to /disks/<name>.";
        };
        encrypted = lib.mkOption {
          type        = lib.types.bool;
          default     = true;
          description = "Wrap the filesystem in a LUKS container.";
        };
        format = lib.mkOption {
          type        = lib.types.str;
          default     = "btrfs";
          description = "Filesystem type passed to mkfs (e.g. ext4, btrfs, xfs).";
        };
        raidMode = lib.mkOption {
          type        = lib.types.int;
          default     = 0;
          description = ''
            mdadm RAID level to use when multiple devices are provided.
            Ignored when only a single device is specified.
          '';
        };
        devices = lib.mkOption {
          type        = lib.types.listOf lib.types.str;
          description = "Ordered list of block-device paths that make up this volume.";
        };
      };
    }));
  };

  config = lib.mkIf (cfg != {}) {
    disko.devices =
      { disk = allDiskEntries; }
      // lib.optionalAttrs (raidConfigs != {}) { mdadm = mdadmEntries; };
  };
}
