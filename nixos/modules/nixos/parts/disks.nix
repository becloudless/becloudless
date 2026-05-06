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

  # Only disks with disko = true are handed to disko
  diskoCfgs    = lib.filterAttrs (_: diskCfg:  diskCfg.disko) cfg;
  nonDiskoCfgs = lib.filterAttrs (_: diskCfg: !diskCfg.disko) cfg;

  allDiskEntries =
    builtins.foldl' (acc: e: acc // e) {}
      (lib.mapAttrsToList mkDiskEntries diskoCfgs);

  raidConfigs  = lib.filterAttrs (_: diskCfg: isRaid diskCfg) diskoCfgs;
  mdadmEntries = lib.mapAttrs mkMdadmEntry raidConfigs;

  # ── non-disko: manual fstab / crypttab / mdadm ──────────────────────────

  # Underlying block device for a non-disko disk (before optional LUKS)
  underlyingDevice = name: diskCfg:
    if isRaid diskCfg then "/dev/md/${name}"
    else builtins.head diskCfg.devices;

  # fileSystems entries
  nonDiskoFileSystems = lib.mapAttrs' (name: diskCfg: {
    name  = diskCfg.path;
    value = {
      device  = if diskCfg.encrypted
                then "/dev/mapper/${name}"
                else underlyingDevice name diskCfg;
      fsType  = diskCfg.format;
      options = [ "defaults" "nofail" ];
    };
  }) nonDiskoCfgs;

  # crypttab entries for encrypted non-disko disks
  encryptedNonDisko  = lib.filterAttrs (_: diskCfg: diskCfg.encrypted) nonDiskoCfgs;
  crypttabLines      = lib.concatStringsSep "\n" (lib.mapAttrsToList (name: diskCfg:
    "${name}  ${underlyingDevice name diskCfg}  none  luks"
  ) encryptedNonDisko);

  # mdadm.conf entries for multi-device non-disko disks
  raidNonDisko       = lib.filterAttrs (_: diskCfg: isRaid diskCfg) nonDiskoCfgs;
  mdadmConfLines     = lib.concatStringsSep "\n" (lib.mapAttrsToList (name: diskCfg:
    "ARRAY /dev/md/${name} level=raid${toString diskCfg.raidMode} num-devices=${toString (builtins.length diskCfg.devices)} devices=${lib.concatStringsSep "," diskCfg.devices}"
  ) raidNonDisko);

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
        location = lib.mkOption {
          type        = lib.types.str;
          default     = "";
          description = "Physical location of the disk(s), e.g. for inventory purposes. No functional effect.";
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
        disko = lib.mkOption {
          type        = lib.types.bool;
          default     = true;
          description = "Whether this disk should be managed by disko (partitioning + formatting). Set to false if the disk is pre-formatted and only needs fstab/crypttab/mdadm wiring.";
        };
      };
    }));
  };

  config = lib.mkIf (cfg != {}) (lib.mkMerge [

    # disko-managed disks
    (lib.mkIf (diskoCfgs != {}) {
      disko.devices =
        { disk = allDiskEntries; }
        // lib.optionalAttrs (raidConfigs != {}) { mdadm = mdadmEntries; };
    })

    # non-disko: fstab
    (lib.mkIf (nonDiskoCfgs != {}) {
      fileSystems = nonDiskoFileSystems;
    })

    # non-disko: crypttab (types.lines → auto-concatenated across modules)
    (lib.mkIf (encryptedNonDisko != {}) {
      environment.etc.crypttab.text = crypttabLines + "\n";
    })

    # non-disko: mdadm RAID arrays
    (lib.mkIf (raidNonDisko != {}) {
      boot.swraid.enable    = true;
      boot.swraid.mdadmConf = mdadmConfLines + "\n";
    })

  ]);
}
