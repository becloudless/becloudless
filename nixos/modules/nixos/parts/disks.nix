{ config, lib, ... }:
let
  cfg = config.bcl.disks;

  isRaid = diskCfg: builtins.length diskCfg.devices > 1;

  # Underlying block device (before optional LUKS)
  underlyingDevice = name: diskCfg:
    if isRaid diskCfg then "/dev/md/${name}"
    else builtins.head diskCfg.devices;

  # fileSystems entries
  fileSystemsEntries = lib.mapAttrs' (name: diskCfg: {
    name  = diskCfg.path;
    value = {
      device  = if diskCfg.encrypted
                then "/dev/mapper/${name}"
                else underlyingDevice name diskCfg;
      fsType  = "auto";
      options = [ "defaults" "nofail" ];
    };
  }) cfg;

  # crypttab entries for encrypted disks
  encryptedCfgs = lib.filterAttrs (_: diskCfg: diskCfg.encrypted) cfg;
  crypttabLines = lib.concatStringsSep "\n" (lib.mapAttrsToList (name: diskCfg:
    "${name}  ${underlyingDevice name diskCfg}  none  luks"
  ) encryptedCfgs);

  # mdadm.conf entries for multi-device disks
  raidCfgs      = lib.filterAttrs (_: diskCfg: isRaid diskCfg) cfg;
  mdadmConfLines = lib.concatStringsSep "\n" (lib.mapAttrsToList (name: diskCfg:
    "ARRAY /dev/md/${name} level=raid${toString diskCfg.raidMode} num-devices=${toString (builtins.length diskCfg.devices)} devices=${lib.concatStringsSep "," diskCfg.devices}"
  ) raidCfgs);

in {
  options.bcl.disks = lib.mkOption {
    default     = {};
    description = "Named data-disk configurations (fstab / crypttab / mdadm wiring).";
    example     = {
      ssd1 = {
        encrypted = true;
        raidMode  = 1;
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
        location = lib.mkOption {
          type        = lib.types.str;
          default     = "";
          description = "Physical location of the disk(s), for inventory purposes. No functional effect.";
        };
        raidMode = lib.mkOption {
          type        = lib.types.int;
          default     = 1;
          description = ''
            mdadm RAID level to use when multiple devices are provided.
            Ignored when only a single device is specified.
          '';
        };
        devices = lib.mkOption {
          type        = lib.types.either lib.types.str (lib.types.listOf lib.types.str);
          apply       = d: if builtins.isString d then [ d ] else d;
          description = "Block-device path(s) that make up this volume. A single string is accepted for the single-device case.";
        };
      };
    }));
  };

  config = lib.mkIf (cfg != {}) (lib.mkMerge [

    # fstab
    { fileSystems = fileSystemsEntries; }

    # crypttab (types.lines → auto-concatenated across modules)
    (lib.mkIf (encryptedCfgs != {}) {
      environment.etc.crypttab.text = crypttabLines + "\n";
    })

    # mdadm RAID arrays
    (lib.mkIf (raidCfgs != {}) {
      boot.swraid.enable    = true;
      boot.swraid.mdadmConf = mdadmConfLines + "\n";
    })

  ]);
}
