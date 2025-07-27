{ inputs, lib, ... }: inputs.yaml.lib.fromYaml ./default.yaml // {
  isoImage.squashfsCompression = "gzip -Xcompression-level 1";
  isoImage.volumeID = lib.mkForce "bcl-iso";
  isoImage.isoName = lib.mkForce "bcl.iso";
}
