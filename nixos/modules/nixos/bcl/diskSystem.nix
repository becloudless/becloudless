{
  config,
  lib,
  pkgs,
  ...
}:
with lib.bcl;
let
  cfg = config.bcl.diskSystem;
  isMultiDevice = (builtins.length cfg.devices) > 1;
  isVirtiofsNix = cfg.nixFsFormat == "virtiofs";
in {
  options.bcl.diskSystem = {
    enable = lib.mkEnableOption "Enable the default settings?";
    encrypted = lib.mkEnableOption "Encrypt disk";
    gpt = lib.mkOption {
       type = lib.types.bool;
       default = true;
    };
    devices = lib.mkOption {
      type = with lib.types; listOf str;
      default = [ ];
    };
    ubootPackage = lib.mkOption {
      type = with lib.types; nullOr package;
      default = null;
      description = "U-Boot package to flash to the beginning of the disk (before partitions).";
    };
    nixFsFormat = lib.mkOption {
      type = lib.types.str;
      default = "ext4";
      description = ''
        Filesystem format used for the /nix partition. Special value
        "virtiofs" skips partitioning a /nix on disk entirely and instead
        mounts /nix from the host over virtiofs (mount tag "nix") - see
        `bcl.vm.vms.<name>.guestNix` on the hypervisor side. In that case
        `devices` still needs a disk for /boot (and the tmpfs root).
      '';
    };
    extraPartitions = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule ({ name, ... }: {
        options = {
          mountpoint = lib.mkOption {
            type = lib.types.str;
            default = "/var/lib/${name}";
            description = "Where to mount this dedicated partition.";
          };
          size = lib.mkOption {
            type = lib.types.str;
            description = "Size of the partition, e.g. \"10G\".";
          };
          format = lib.mkOption {
            type = lib.types.str;
            default = "ext4";
            description = "Filesystem format (ext4 or xfs, per what cadvisor/Longhorn support).";
          };
        };
      }));
      default = { };
      description = ''
        Experimental. Extra dedicated partitions created directly on disk
        instead of relying on impermanence bind-mounts from /nix. Needed
        when nixFsFormat = "virtiofs", since several things cannot work on
        top of virtiofs (a FUSE filesystem):
        - cadvisor (used by kubelet) does not recognize virtiofs-backed
          directories, failing with "could not find device in cached
          partitions map" (affects /var/lib/kubelet).
        - overlayfs (containerd's snapshotter) cannot mount its
          upperdir/workdir/lowerdir on virtiofs, failing with
          "failed to mount rootfs component: ... invalid argument" (affects
          /var/lib/containerd).
        Currently only supported with gpt = true and a single device.
      '';
    };
  };

  ###################

  config = lib.mkIf cfg.enable {

    services.udev.extraRules =
    ''
      # make disks stop spinning after 3h. 246=3h, 127=most powerful mode that still allow going into standby
      ACTION=="add|change", SUBSYSTEM=="block", KERNEL=="sd*[!0-9]", ATTR{queue/rotational}=="1", RUN+="${pkgs.hdparm}/bin/hdparm -B 127 -S 246 /dev/%k"

      # Seagate.
      # check settings with: openSeaChest_PowerControl -d /dev/sda --showEPCSettings
      # check state with: openSeaChest_PowerControl -d /dev/sda --checkPowerMode
      # stop spinning now: openSeaChest_PowerControl -d /dev/sdX --transitionPower standby
      #
      # idle_b=park heads, idle_c=reduce motor speed, standby_z=stop spinning
      # 120000=20min, 600000=1.6h 900000=2.5h
      ACTION=="add|change", SUBSYSTEM=="block", KERNEL=="sd*[!0-9]", ATTR{queue/rotational}=="1", RUN+="${pkgs.openseachest}/bin/openSeaChest_PowerControl -d /dev/%k --idle_b 120000 --idle_c 600000 --standby_z 900000"

    '';

    fileSystems."/nix".neededForBoot = true;

    assertions = [
      {
        assertion = cfg.extraPartitions == { } || cfg.gpt;
        message = "bcl.diskSystem.extraPartitions currently requires bcl.diskSystem.gpt = true.";
      }
      {
        assertion = cfg.extraPartitions == { } || !isMultiDevice;
        message = "bcl.diskSystem.extraPartitions currently only supports a single device.";
      }
    ];

    # disko do not set it when msdos table partition
    boot.loader.grub.devices = lib.mkIf (!cfg.gpt) cfg.devices;

    disko.devices = {
      nodev = {
        "/" = {
          fsType = "tmpfs";
          mountOptions = ["defaults" "size=5G" "mode=755"];
        };
      } // lib.optionalAttrs isVirtiofsNix {
        "/nix" = {
          fsType = "virtiofs";
          device = "nix";
        };
      };

      disk = let

        bootContent = if isMultiDevice then {
          type = "mdraid";
          name = "boot";
        } else {
          type = "filesystem";
          format = "vfat";
          mountOptions = [ "umask=0077" ];
          mountpoint = "/boot";
        };

        nixContent = if isMultiDevice then {
          type = "mdraid";
          name = "nix";
        } else if cfg.encrypted then {
          type = "luks";
          name = "nix";
          settings.allowDiscards = true;
          passwordFile = "/root/secret.key"; # the install script provide this file
          content = {
            type = "filesystem";
            format = cfg.nixFsFormat;
            mountpoint = "/nix";
          };
        } else {
          type = "filesystem";
          format = cfg.nixFsFormat;
          mountpoint = "/nix";
        };

        diskContent = if cfg.gpt then {
          type = "gpt";
          partitions = {
            MBR = {
              # Raw gap consumed by u-boot binaries; no filesystem.
              # 16 MiB keeps us safely past u-boot.itb (sector 16384 = 8 MiB).
              size = "16M";
              type = "EF02";
              priority = 1;
            };
            ESP = {
              size = if isVirtiofsNix && cfg.extraPartitions == { } then "100%" else "1G";
              type = "EF00";
              content = bootContent;
            };
          } // lib.mapAttrs (_: p: {
            size = p.size;
            content = {
              type = "filesystem";
              format = p.format;
              mountpoint = p.mountpoint;
            };
          }) cfg.extraPartitions // lib.optionalAttrs (!isVirtiofsNix) {
            nix = {
              size = "100%";
              content = nixContent;
            };
          };
        } else {
          type = "table";
          format = "msdos";
          partitions = [ # MSDOS
           ({
             name = "boot";
             part-type = "primary";
             start = "1M";
             bootable = true;
             content = bootContent;
           } // lib.optionalAttrs (!isVirtiofsNix) { end = "1G"; })
         ] ++ lib.optional (!isVirtiofsNix) {
             name = "nix";
             part-type = "primary";
             start = "1G";
             content = nixContent;
           };
        };

        mkDisk = index: device: {
          name = if isMultiDevice then "main${toString index}" else "main";
          value = {
            type = "disk";
            device = device;
            content = diskContent;
            postCreateHook = if cfg.ubootPackage != null then ''
              echo "Writing u-boot to ${device}"
              ${pkgs.coreutils}/bin/dd if=${cfg.ubootPackage}/idbloader.img of=${device} seek=64    conv=fsync,notrunc
              ${pkgs.coreutils}/bin/dd if=${cfg.ubootPackage}/u-boot.itb    of=${device} seek=16384 conv=fsync,notrunc
            '' else ''
              #echo "Erasing MBR gap on ${device} (preserving GPT)"
              #${pkgs.coreutils}/bin/dd if=/dev/zero of=${device} bs=1M seek=1 count=15 conv=fsync,notrunc
            '';
          };
        };
      in builtins.listToAttrs (lib.imap1 (i: v: (mkDisk i v)) cfg.devices);

      mdadm = lib.mkIf isMultiDevice ({
        boot = {
          type = "mdadm";
          level = 1;
          metadata = "1.0";
          content = {
            type = "filesystem";
            format = "vfat";
            mountpoint = "/boot";
          };
        };
      } // lib.optionalAttrs (!isVirtiofsNix) {
        nix = {
          type = "mdadm";
          level = 0;
          content = {
            type = "gpt";
            partitions.primary = {
              size = "100%";
              content = if cfg.encrypted then {
                type = "luks";
                name = "nix";
                settings.allowDiscards = true;
                passwordFile = "/root/secret.key"; # the install script provide this file
                content = {
                  type = "filesystem";
                  format = cfg.nixFsFormat;
                  mountpoint = "/nix";
                };
              } else {
                type = "filesystem";
                format = cfg.nixFsFormat;
                mountpoint = "/nix";
              };
            };
          };
        };
      });

    };
  };
}


