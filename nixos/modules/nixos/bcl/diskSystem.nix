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
  isVirtiofsNix = cfg.nix.format == "virtiofs";
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
    nix = lib.mkOption {
      type = lib.types.submodule {
        options = {
          format = lib.mkOption {
            type = lib.types.str;
            default = "ext4";
            description = ''
              Filesystem format used for the /nix partition. Special value
              "virtiofs" skips partitioning a /nix on disk entirely and
              instead mounts /nix from the host over virtiofs (mount tag
              "nix") - see `bcl.vm.vms.<name>.guestNix` on the hypervisor
              side. In that case `devices` still needs a disk for /boot
              (and the tmpfs root).
            '';
          };
          size = lib.mkOption {
            type = lib.types.str;
            default = "100%";
            description = ''
              Size of the /nix partition, e.g. "100%" (consume the rest of
              the disk, the default) or a fixed size like "300G" (e.g. to
              leave room for `lvmPool` on the same disk).
            '';
          };
        };
      };
      default = { };
      description = "Options for the /nix partition.";
    };
    persistRoot = lib.mkOption {
      type = lib.types.str;
      default = "/nix";
      description = ''
        Root path used by roles (e.g. serverKube/serverKubeContainerd) for
        `environment.persistence.<persistRoot>` impermanence bind-mounts.
        Normally "/nix" (the default), but should be set to e.g. "/persist"
        when nix.format = "virtiofs" and a dedicated real-filesystem
        `extraDisks` volume is mounted at /persist - since several things
        (cadvisor/kubelet, containerd's overlayfs snapshotter) cannot work
        bind-mounted from a virtiofs-backed /nix.
      '';
    };
    lvmPool = lib.mkOption {
      type = lib.types.nullOr (lib.types.submodule {
        options = {
          vgName = lib.mkOption {
            type = lib.types.str;
            default = "vmpool";
            description = "Name of the LVM volume group.";
          };
          poolName = lib.mkOption {
            type = lib.types.str;
            default = "thinpool";
            description = "Name of the LVM thin pool logical volume within the volume group.";
          };
        };
      });
      default = null;
      description = ''
        Experimental. When set, creates an LVM volume group (a dedicated
        partition consuming the rest of the disk, after /nix - see
        `nix.size`) with a thin pool, used by `bcl.vm.vms.<name>.volumes` on
        this host to back per-VM thin logical volumes attached as extra
        virtio-blk block devices to guests. Currently only supported with
        gpt = true, a single device, and `nix.size` != "100%".
      '';
    };
    extraDisks = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule ({ name, ... }: {
        options = {
          serial = lib.mkOption {
            type = lib.types.str;
            default = name;
            description = ''
              Serial number of the virtio-blk disk to use (matches
              `/dev/disk/by-id/virtio-<serial>`) - see
              `bcl.vm.vms.<name>.volumes` on the hypervisor side, which
              attaches host-LV-backed block devices with a matching serial.
            '';
          };
          mountpoint = lib.mkOption {
            type = lib.types.str;
            description = "Where to mount this whole disk.";
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
        Experimental. Extra whole virtio-blk disks (identified by serial,
        NOT partitions of the main disk(s)) formatted and mounted directly.
        Needed when nix.format = "virtiofs", since several things cannot
        work on top of virtiofs (a FUSE filesystem):
        - cadvisor (used by kubelet) does not recognize virtiofs-backed
          directories, failing with "could not find device in cached
          partitions map".
        - overlayfs (containerd's snapshotter) cannot mount its
          upperdir/workdir/lowerdir on virtiofs, failing with
          "failed to mount rootfs component: ... invalid argument".
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

    # impermanence requires persistentStoragePath filesystems to have
    # neededForBoot = true - set it for /nix and (unconditionally) for all
    # extraDisks, since any of them may be used as persistRoot.
    fileSystems = { "/nix".neededForBoot = true; }
      // lib.mapAttrs' (_: d: lib.nameValuePair d.mountpoint { neededForBoot = true; }) cfg.extraDisks;

    assertions = [
      {
        assertion = cfg.lvmPool == null || cfg.gpt;
        message = "bcl.diskSystem.lvmPool currently requires bcl.diskSystem.gpt = true.";
      }
      {
        assertion = cfg.lvmPool == null || !isMultiDevice;
        message = "bcl.diskSystem.lvmPool currently only supports a single device.";
      }
      {
        assertion = cfg.lvmPool == null || cfg.nix.size != "100%";
        message = "bcl.diskSystem.lvmPool requires bcl.diskSystem.nix.size to be a fixed size (not \"100%\"), to leave room for the LVM pool.";
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
            format = cfg.nix.format;
            mountpoint = "/nix";
          };
        } else {
          type = "filesystem";
          format = cfg.nix.format;
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
              size = if isVirtiofsNix then "100%" else "1G";
              type = "EF00";
              content = bootContent;
            };
          } // lib.optionalAttrs (!isVirtiofsNix) {
            nix = {
              size = cfg.nix.size;
              content = nixContent;
            };
          } // lib.optionalAttrs (cfg.lvmPool != null) {
            lvm = {
              size = "100%";
              content = {
                type = "lvm_pv";
                vg = cfg.lvmPool.vgName;
              };
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
      in builtins.listToAttrs (lib.imap1 (i: v: (mkDisk i v)) cfg.devices)
      // lib.mapAttrs (_: d: {
        type = "disk";
        device = "/dev/disk/by-id/virtio-${d.serial}";
        content = {
          type = "filesystem";
          format = d.format;
          mountpoint = d.mountpoint;
        };
      }) cfg.extraDisks;

      lvm_vg = lib.optionalAttrs (cfg.lvmPool != null) {
        ${cfg.lvmPool.vgName} = {
          type = "lvm_vg";
          lvs.${cfg.lvmPool.poolName} = {
            size = "100%";
            lvm_type = "thin-pool";
          };
        };
      };

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
                  format = cfg.nix.format;
                  mountpoint = "/nix";
                };
              } else {
                type = "filesystem";
                format = cfg.nix.format;
                mountpoint = "/nix";
              };
            };
          };
        };
      });

    };
  };
}


