{ lib, config, pkgs, ... }:
let
  cfg = config.bcl.data;

  # Per-entry helpers
  mkEntryConfig = dataName: entryCfg:
    let
      mountPoint = if entryCfg.mount != "" then entryCfg.mount else "/data/${dataName}";
      devices = lib.mapAttrs (_: v: v.path) (lib.filterAttrs (_: v: v.path != "") entryCfg.devices);
      deviceModes = lib.mapAttrs (_: v: v.mode or "rw") entryCfg.devices;

      fileSystemsEntries = lib.mapAttrs' (name: path: {
        name = "/disks/${name}";
        value = {
          device = if entryCfg.encryption then "/dev/mapper/${name}" else path;
          fsType = "auto";
          options = [ (deviceModes.${name}) "defaults" "nofail" ];
        };
      }) devices;

      crypttabLines = lib.mapAttrsToList (name: path: "${name}  ${path}          none luks") devices;

      mergerfsFileSystem = lib.optionalAttrs (devices != {}) {
        "${mountPoint}" = {
          device = "/var/empty";
          fsType = "fuse.mergerfs";
          options = [ "rw" "minfreespace=50G" "category.create=msplfs" "defaults" "allow_other" ];
        };
      };

      mergerServices = lib.mapAttrs' (name: _: {
        name = "data-${dataName}-merger@${name}";
        value = {
          description = "Merge /disks/${name} into mergerfs pool at ${mountPoint}";
          after = [ "disks-${name}.mount" ];
          requires = [ "disks-${name}.mount" ];
          wantedBy = [ "disks-${name}.mount" ];
          path = with pkgs; [ attr ];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
          };
          script = ''
            # https://trapexit.github.io/mergerfs/latest/runtime_interface/#setting
            echo "Adding /disks/${name} to mergerfs"
            setfattr -n user.mergerfs.branches -v "+>/disks/${name}=RW" ${mountPoint}/.mergerfs
          '';
        };
      }) devices;
    in {
      inherit fileSystemsEntries mergerfsFileSystem mergerServices crypttabLines;
    };

  allEntries = lib.mapAttrsToList mkEntryConfig cfg;

  allFileSystems = lib.mkMerge (map (e: e.fileSystemsEntries // e.mergerfsFileSystem) allEntries);
  allServices   = lib.mkMerge (map (e: e.mergerServices) allEntries);
  allCrypttab   = lib.concatStringsSep "\n" (lib.flatten (map (e: e.crypttabLines) allEntries));

  anyCryptab    = lib.any (e: e.crypttabLines != []) allEntries;
  anyDevices    = lib.any (e: e.mergerfsFileSystem != {}) allEntries;

  entrySubmodule = { ... }: {
    options = {
      mount = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "Override the mergerfs mount point. Defaults to /data/<name>.";
      };

      encryption = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Whether devices are LUKS-encrypted. When enabled, devices are opened via /dev/mapper and registered in crypttab.";
      };

      devices = lib.mkOption {
        type = lib.types.attrsOf (lib.types.submodule ({ ... }: {
          options = {
            path = lib.mkOption {
              type = lib.types.str;
              description = "Underlying block device path for the data device.";
            };
            mode = lib.mkOption {
              type = lib.types.enum [ "ro" "rw" ];
              default = "rw";
              description = "Mount mode used for the underlying /disks/* mounts (ro/rw).";
            };
            location = lib.mkOption {
              type = lib.types.str;
              default = "";
              description = "Physical location of the device.";
            };
          };
        }));
        default = {};
        example = {
          nvme1 = { path = "/dev/disk/by-id/nvme-dsfsdfs00"; mode = "rw"; };
          hdd1  = { path = "/dev/disk/by-id/ata-sdfdsQBJW8L1T"; mode = "ro"; };
        };
      };
    };
  };
in {
  options.bcl.data = lib.mkOption {
    type = lib.types.attrsOf (lib.types.submodule entrySubmodule);
    default = {};
    example = {
      main = {
        encryption = true;
        devices.nvme1 = { path = "/dev/disk/by-id/nvme-dsfsdfs00"; mode = "rw"; };
      };
    };
  };

  config = lib.mkMerge [
    { fileSystems = allFileSystems; }
    (lib.mkIf anyCryptab { environment.etc.crypttab.text = allCrypttab + "\n"; })
    (lib.mkIf anyDevices { systemd.services = allServices; })
  ];
}
