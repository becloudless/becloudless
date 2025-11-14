{ lib, config, ... }:
let
  cfg = config.bcl.dataDisks;
  disks = lib.filterAttrs (_: v: v != "") cfg;
  fileSystemsEntries = builtins.listToAttrs (lib.mapAttrsToList (name: _: {
    name = "/disks/${name}";
    value = {
      device = "/dev/mapper/${name}";
      fsType = "btrfs";
      options = [ "defaults" "nofail" ];
    };
  }) disks);
  crypttabText = lib.concatStringsSep "\n" (lib.mapAttrsToList (name: path: "${name}  ${path}          none luks") disks);
  hasDataDisks = disks != {};
  # /data mounts moved from system definition; enabled only when data disks defined
  mkBindData = from: to: {
    name = "/data/${to}";
    value = {
      device = "${from}";
      fsType = "none";
      options = ["bind" "noauto"];
    };
  };
  mkMergeData = type: {
    name = "/data/${type}";
    value = {
      device = "/disks/*/${type}";
      fsType = "fuse.mergerfs";
      options = [ "ro" "minfreespace=50G" "category.create=msplfs" "noauto" ];
    };
  };
  dataFileSystems = builtins.listToAttrs [
    (mkBindData "/disks/hdd5" "download")
    (mkBindData "/disks/hdd5/backup" "backup")
    (mkBindData "/disks/nvme1/cache" "cache")
    (mkMergeData "audio")
    (mkMergeData "video")
    (mkMergeData "image")
  ];
  mountBindsService = {
    systemd.services."mount-binds" = {
      enable = true;
      script = ''
        systemctl start data-download.mount
        systemctl start data-backup.mount
        systemctl start data-cache.mount
        systemctl start data-audio.mount
        systemctl start data-video.mount
        systemctl start data-image.mount
      '';
      after = [ "fs-local.target" ];
      wantedBy = ["multi-user.target"];
    };
  };
in {
  options.bcl.dataDisks = lib.mkOption {
    type = lib.types.attrsOf lib.types.str;
    default = {};
    example = {
      nvme1 = "/dev/disk/by-id/nvme-dsfsdfs00";
      hdd1 = "/dev/disk/by-id/ata-sdfdsQBJW8L1T";
    };
    description = "Mount encrypted data files to /disks/{name}. Also provides /data binds & mergerfs mounts when any data disk is defined.";
  };

  config = lib.mkMerge [
    { fileSystems = fileSystemsEntries; }
    (lib.mkIf (crypttabText != "") { environment.etc.crypttab.text = crypttabText + "\n"; })
    (lib.mkIf hasDataDisks { fileSystems = dataFileSystems; })
    (lib.mkIf hasDataDisks mountBindsService)
  ];
}
