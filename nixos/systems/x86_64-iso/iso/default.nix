{ config, lib, pkgs, ... }: {

  bcl.role = {
    enable = true;
    name = "install";
  };

  # faster compression
  isoImage.squashfsCompression = "gzip -Xcompression-level 1";

  isoImage.volumeID = lib.mkForce "bcl-iso";
  isoImage.isoName = lib.mkForce "bcl.iso";
}
