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
  dataTypes = [ "Audio" "Videos" "Images" "Games" "Software" "Caches" ];
  mkMergeData = type: {
    name = "/data/${type}";
    value = {
      device = "/var/empty";
      fsType = "fuse.mergerfs";
      options = [ "rw" "minfreespace=50G" "category.create=msplfs" "defaults" "allow_other" "use_ino" "cache.files=partial" "dropcacheonclose=true" "category.create=mfs" ];
    };
  };
  mergerfsFileSystems = builtins.listToAttrs (map mkMergeData dataTypes);
  diskNames = lib.attrNames disks;
  # Generate systemd service to dynamically add disks to mergerfs pools
  mergerfsUpdateService = {
    systemd.services."mergerfs-update-pools" = {
      enable = true;
      description = "Dynamically add disks to mergerfs pools";
      script = ''
        # Wait a bit to ensure mergerfs mounts are ready
        sleep 2

        # For each data type, update the mergerfs pool with available disks
        for dataType in ${lib.concatStringsSep " " dataTypes}; do
          mountpoint="/data/$dataType"
          controlFile="$mountpoint/.mergerfs"

          if [ -f "$controlFile" ]; then
            # Build the list of available disk paths for this data type
            paths=""
            for diskName in ${lib.concatStringsSep " " diskNames}; do
              diskPath="/disks/$diskName/$dataType"
              if [ -d "$diskPath" ]; then
                if [ -z "$paths" ]; then
                  paths="$diskPath"
                else
                  paths="$paths:$diskPath"
                fi
              fi
            done

            # Update mergerfs with the new paths if any exist
            if [ -n "$paths" ]; then
              echo "Updating $mountpoint with paths: $paths"
              echo "$paths" > "$controlFile/branches"
            fi
          fi
        done
      '';
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      after = [ "local-fs.target" ] ++ (map (name: "disks-${name}.mount") diskNames);
      wants = map (name: "disks-${name}.mount") diskNames;
      wantedBy = [ "multi-user.target" ];
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
    (lib.mkIf hasDataDisks mergerfsUpdateService)
  ];
}
