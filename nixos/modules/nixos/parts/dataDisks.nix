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
  hasDataDisks = disks != {};
  mkMergeData = type: {
    name = "/data/${type}";
    value = {
      device = "/disks/*/${type}";
      fsType = "fuse.mergerfs";
      options = [ "ro" "minfreespace=50G" "category.create=msplfs" "noauto" ];
    };
  };
  mergerfsFileSystems = builtins.listToAttrs [
    (mkMergeData "Audio")
    (mkMergeData "Videos")
    (mkMergeData "Images")
    (mkMergeData "Games")
    (mkMergeData "Software")
    (mkMergeData "Caches")
  ];
  mountMergerfsService = {
    systemd.services."mount-mergerfs" = {
      enable = true;
      script = ''
        systemctl start data-Caches.mount
        systemctl start data-Audio.mount
        systemctl start data-Videos.mount
        systemctl start data-Images.mount
        systemctl start data-Games.mount
        systemctl start data-Software.mount
      '';
      after = [ "fs-local.target" ];
      wantedBy = ["multi-user.target"];
    };
  };
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
    { fileSystems = fileSystemsEntries; }
    (lib.mkIf (crypttabText != "") { environment.etc.crypttab.text = crypttabText + "\n"; })
    (lib.mkIf hasDataDisks { fileSystems = mergerfsFileSystems; })
    (lib.mkIf hasDataDisks mountMergerfsService)
  ];
}
