{ config, lib, pkgs, ... }: {

  bcl.system = {
    enable = true;
    hardware = "loksing-n100";
    role = "srv";
    ids = "macs=a8:b8:e0:01:e7:e9";
    devices = [ "/dev/disk/by-id/nvme-CT4000P3PSSD8_2328E6EEE0E1" ];
  };


#  lmr.role = {
#    enable = true;
#    name = "install";
#  };

  # faster compression
  isoImage.squashfsCompression = "gzip -Xcompression-level 1";
  # isoImage.squashfsCompression = "zstd -Xcompression-level 6";

  isoImage.volumeID = lib.mkForce "bcl-iso";
  isoImage.isoName = lib.mkForce "bcl.iso";
}
