{ config, lib, pkgs, ... }: {

  bcl.role = {
    enable = true;
    name = "install";
  };

  # faster compression, we do not care about size
  isoImage.squashfsCompression = "gzip -Xcompression-level 1";

  isoImage.volumeID = lib.mkForce "bcl-iso";
  isoImage.isoName = lib.mkForce "bcl.iso";
}
