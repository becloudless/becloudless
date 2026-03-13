{ modulesPath, lib, ... }:
{
  # nix build .#nixosConfigurations.install.config.system.build.isoImage --impure
  imports = [ "${modulesPath}/installer/cd-dvd/installation-cd-minimal.nix" ];
  bcl.role.name = "install";

  image.baseName = lib.mkForce "bcl";
  isoImage.squashfsCompression = "gzip -Xcompression-level 1";
  isoImage.volumeID = lib.mkForce "bcl-iso";
}

