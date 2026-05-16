{ config, lib, pkgs, ... }:
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
      options = [ diskCfg.mode "defaults" "nofail" ];
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
        mode = lib.mkOption {
          type        = lib.types.enum [ "rw" "ro" ];
          default     = "rw";
          description = "Mount mode: rw (read-write) or ro (read-only).";
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
        scrubInterval = lib.mkOption {
          type        = lib.types.nullOr lib.types.str;
          default     = "monthly";
          example     = "weekly";
          description = ''
            systemd OnCalendar expression for periodic scrubs.
            Defaults to "monthly". Set to null to disable scrubbing for this disk.
            Scrub runs only when the mounted filesystem is BTRFS.
          '';
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

    # BTRFS scrub timers (one timer+service pair per disk with scrubInterval set)
    (let
      scrubDisks = lib.filterAttrs (_: d: d.scrubInterval != null) cfg;
    in lib.mkIf (scrubDisks != {}) {
      environment.systemPackages = [ pkgs.btrfs-progs ];

      systemd.services = lib.mapAttrs' (name: diskCfg:
        let safeName = "disk-scrub-${name}";
        in lib.nameValuePair safeName {
          description = "BTRFS scrub for ${diskCfg.path}";
          after        = [ "local-fs.target" ];

          serviceConfig = {
            Type = "oneshot";
            ExecStart = pkgs.writeShellScript "btrfs-scrub-${name}" ''
              fstype=$(${pkgs.util-linux}/bin/findmnt -n -o FSTYPE --target ${diskCfg.path} 2>/dev/null || true)
              if [[ "$fstype" != "btrfs" ]]; then
                echo "Skipping scrub for ${diskCfg.path}: filesystem is '$fstype'"
                exit 0
              fi

              # Resume an interrupted scrub; fall back to a fresh one
              if ! ${pkgs.btrfs-progs}/bin/btrfs scrub resume -B ${diskCfg.path} 2>/dev/null; then
                echo "Starting fresh scrub for ${diskCfg.path}"
                ${pkgs.btrfs-progs}/bin/btrfs scrub start -B ${diskCfg.path}
              fi
            '';
          };
        }
      ) scrubDisks;

      systemd.timers = lib.mapAttrs' (name: diskCfg:
        let safeName = "disk-scrub-${name}";
        in lib.nameValuePair safeName {
          description = "Periodic BTRFS scrub timer for ${diskCfg.path}";
          wantedBy    = [ "timers.target" ];
          timerConfig = {
            OnCalendar = diskCfg.scrubInterval;
            # Run on next boot if the scheduled time was missed (machine was off)
            Persistent = true;
            # Add stable jitter to avoid all hosts scrubbing simultaneously
            RandomizedDelaySec = "7d";
            FixedRandomDelay = true;
            Unit       = "${safeName}.service";
          };
        }
      ) scrubDisks;
    })

  ]);
}
