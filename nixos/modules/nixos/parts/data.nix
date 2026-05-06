{ lib, config, pkgs, ... }:
let
  cfg = config.bcl.data;
  # Accept attrset with { path, mode } and normalize to maps of paths and modes
  disks = lib.mapAttrs (_: v: v.path) (lib.filterAttrs (_: v: v.path != "") cfg.disks);
  diskModes = lib.mapAttrs (_: v: v.mode or "rw") cfg.disks;
  fileSystemsEntries = builtins.listToAttrs (lib.mapAttrsToList (name: path: {
    name = "/disks/${name}";
    value = {
      device = if cfg.encryption then "/dev/mapper/${name}" else path;
      fsType = "auto";
      options = [ (diskModes.${name}) "defaults" "nofail" ];
    };
  }) disks);
  crypttabText = lib.concatStringsSep "\n" (lib.mapAttrsToList (name: path: "${name}  ${path}          none luks") disks);

  mergerfsFileSystem = {
    "/data" = {
      device = "/var/empty";
      fsType = "fuse.mergerfs";
      options = [ "rw" "minfreespace=50G" "category.create=msplfs" "defaults" "allow_other" ];
    };
  };

  # Services to add disks to mergerfs when mounted
  dataMergerServices = builtins.listToAttrs (lib.mapAttrsToList (name: _: {
    name = "data-merger@${name}";
    value = {
      description = "Merge /disks/${name} into mergerfs pool at /data";
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
        setfattr -n user.mergerfs.branches -v "+>/disks/${name}=RW" /data/.mergerfs
      '';
    };
  }) disks);
in {
  options.bcl.data = {
    encryption = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Whether disks are LUKS-encrypted. When enabled, devices are opened via /dev/mapper and registered in crypttab.";
    };

    disks = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule ({ ... }: {
        options = {
          path = lib.mkOption {
            type = lib.types.str;
            description = "Underlying block device path for the data disk.";
          };
          mode = lib.mkOption {
            type = lib.types.enum [ "ro" "rw" ];
            default = "rw";
            description = "Mount mode used for the underlying /disks/* mounts (ro/rw).";
          };
          location = lib.mkOption {
            type = lib.types.str;
            default = "";
            description = "Physical location of the disk.";
          };
        };
      }));
      default = {};
      example = {
        nvme1 = { path = "/dev/disk/by-id/nvme-dsfsdfs00"; mode = "rw"; };
        hdd1 = { path = "/dev/disk/by-id/ata-sdfdsQBJW8L1T"; mode = "ro"; };
      };
    };
  };

  config = lib.mkMerge [
    { fileSystems = fileSystemsEntries; }
    (lib.mkIf (cfg.encryption && crypttabText != "") { environment.etc.crypttab.text = crypttabText + "\n"; })
    (lib.mkIf (disks != {}) {
      fileSystems = mergerfsFileSystem;
      systemd.services = dataMergerServices;
    })
  ];
}
