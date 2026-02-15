{ lib, config, ... }:
let
  cfg = config.bcl.dataDisks;
  # Accept attrset with { path, mode } and normalize to maps of paths and modes
  disks = lib.mapAttrs (_: v: v.path) (lib.filterAttrs (_: v: v.path != "") cfg);
  diskModes = lib.mapAttrs (_: v: v.mode or "rw") cfg;
  fileSystemsEntries = builtins.listToAttrs (lib.mapAttrsToList (name: _: {
    name = "/disks/${name}";
    value = {
      device = "/dev/mapper/${name}";
      fsType = "btrfs";
      options = [ (diskModes.${name}) "defaults" "nofail" ];
    };
  }) disks);
  crypttabText = lib.concatStringsSep "\n" (lib.mapAttrsToList (name: path: "${name}  ${path}          none luks") disks);

  dataTypes = [ "Backups" "Audio" "Videos" "Images" "Games" "Software" "Caches" ];
  mkMergeData = type: {
    name = "/data/${type}";
    value = {
      device = "/var/empty";
      fsType = "fuse.mergerfs";
      options = [ "rw" "minfreespace=50G" "category.create=msplfs" "defaults" "allow_other" ];
    };
  };
  mergerfsFileSystems = builtins.listToAttrs (map mkMergeData dataTypes);
in {
  options.bcl.dataDisks = lib.mkOption {
    type = lib.types.attrsOf (lib.types.submodule ({ ... }: {
      options = {
        path = lib.mkOption {
          type = lib.types.str;
          description = "Underlying block device path for the encrypted data disk.";
        };
        mode = lib.mkOption {
          type = lib.types.enum [ "ro" "rw" ];
          default = "rw";
          description = "Mount mode used for the underlying /disks/* mounts (ro/rw).";
        };
      };
    }));
    default = {};
    example = {
      nvme1 = { path = "/dev/disk/by-id/nvme-dsfsdfs00"; mode = "rw"; };
      hdd1 = { path = "/dev/disk/by-id/ata-sdfdsQBJW8L1T"; mode = "ro"; };
    };
  };

  config = lib.mkMerge [
    (lib.mkIf (crypttabText != "") { environment.etc.crypttab.text = crypttabText + "\n"; })
    (lib.mkIf (disks != {}) { fileSystems = mergerfsFileSystems; })
    {
      fileSystems = fileSystemsEntries;

      systemd.services."data-merger@" = {
        enable = true;
        path = with pkgs; [ gawk util-linux  ];
        serviceConfig.ExecStart =
          let
            script = pkgs.writeScript "data-merger" ''
              #!${pkgs.runtimeShell}

              DISK_MOUNT=/disks/$1

              for type in ${lib.concatStringsSep " " dataTypes}; do
                if [ -d "$DISK_MOUNT/$type" ]; then
                  echo "Adding $DISK_MOUNT/$type to mergerfs"
                  setfattr -n user.mergerfs.branches -v "'+<$DISK_MOUNT/$type=RW /data/$type/.mergerfs
                fi
              done
            '';
          in "${script} %i";
      };
    }
  ];
}
