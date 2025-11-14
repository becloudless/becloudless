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
  mkMergeData = type: {
    name = "/data/${type}";
    value = {
      device = "/disks/*/${type}";
      fsType = "fuse.mergerfs";
      options = [ "ro" "minfreespace=50G" "category.create=msplfs" "noauto" ];
    };
  };
  mergerfsFileSystems = builtins.listToAttrs [
    (mkMergeData "audio")
    (mkMergeData "video")
    (mkMergeData "image")
  ];
  mountMergerfsService = {
    systemd.services."mount-mergerfs" = {
      enable = true;
      script = ''
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
    description = "Mount encrypted data files to /disks/{name}. Also provides mergerfs mountsto data/* folders";
  };

  config = lib.mkMerge [
    { fileSystems = fileSystemsEntries; }
    (lib.mkIf (crypttabText != "") { environment.etc.crypttab.text = crypttabText + "\n"; })
    (lib.mkIf hasDataDisks { fileSystems = mergerfsFileSystems; })
    (lib.mkIf hasDataDisks mountMergerfsService)
  ];
}
