{
  config,
  lib,
  pkgs,
  ...
}:
with lib.bcl;
let
  cfg = config.bcl.disk;
  isMultiDevice = (builtins.length cfg.devices) > 1;
in {
  options.bcl.disk = {
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
  };

  ###################

  config = lib.mkIf cfg.enable {

    services.udev.extraRules =
    ''
      # make disks stop spinning after 3h. 246=3h, 127=most powerful mode that still allow going into standby
      ACTION=="add|change", SUBSYSTEM=="block", KERNEL=="sd[a-z]*", ATTR{queue/rotational}=="1", RUN+="${pkgs.hdparm}/bin/hdparm -B 127 -S 246 /dev/%k"

      # Seagate.
      # check settings with: openSeaChest_PowerControl -d /dev/sda --showEPCSettings
      # check state with: openSeaChest_PowerControl -d /dev/sda --checkPowerMode
      # stop spinning now: openSeaChest_PowerControl -d dev/sdX --transitionPower standby
      #
      # idle_b=park heads, idle_c=reduce motor speed, standby_z=stop spinning
      # 120000=20min, 600000=1.6h 900000=2.5h
      ACTION=="add|change", SUBSYSTEM=="block", KERNEL=="sd[a-z]*", ATTR{queue/rotational}=="1", RUN+="${pkgs.openseachest}/bin/openSeaChest_PowerControl -d /dev/%k --idle_b 120000 --idle_c 600000 --standby_z 900000"

    '';

    fileSystems."/nix".neededForBoot = true;

    # disko do not set it when msdos table partition
    boot.loader.grub.devices = lib.mkIf (!cfg.gpt) cfg.devices;

    disko.devices = {
      nodev = {
        "/" = {
          fsType = "tmpfs";
          mountOptions = ["defaults" "size=5G" "mode=755"];
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
            format = "ext4";
            mountpoint = "/nix";
          };
        } else {
          type = "filesystem";
          format = "ext4";
          mountpoint = "/nix";
        };

        diskContent = if cfg.gpt then {
          type = "gpt";
          partitions = {
            MBR = {
              size = "1M";
              type = "EF02";
              priority = 1;
            };
            ESP = {
              size = "1G";
              type = "EF00";
              content = bootContent;
            };
            nix = {
              size = "100%";
              content = nixContent;
            };
          };
        } else {
          type = "table";
          format = "msdos";
          partitions = [ # MSDOS
           {
             name = "boot";
             part-type = "primary";
             start = "1M";
             end = "1G";
             bootable = true;
             content = bootContent;
           }
           {
             name = "nix";
             part-type = "primary";
             start = "1G";
             content = nixContent;
           }
         ];
        };

        mkDisk = index: device: {
          name = if isMultiDevice then "main${toString index}" else "main";
          value = {
            type = "disk";
            device = device;
            content = diskContent;
          };
        };
      in builtins.listToAttrs (lib.imap1 (i: v: (mkDisk i v)) cfg.devices);

      mdadm = lib.mkIf isMultiDevice {
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
                  format = "ext4";
                  mountpoint = "/nix";
                };
              } else {
                type = "filesystem";
                format = "ext4";
                mountpoint = "/nix";
              };
            };
          };
        };
      };

    };
  };
}


