# Replacement of the deprecated nixos-generators (upstreamed in nixpkgs since 25.05).
# snowfall-lib builds the virtual systems (x86_64-iso, aarch64-iso, ...) with `inputs.nixos-generators.nixosGenerate`,
# only the formats used by `bcl nixos iso` are provided.
{ nixpkgs }:
let
  formatAttrOption = { lib, ... }: {
    options.formatAttr = lib.mkOption {
      type = lib.types.str;
      internal = true;
      description = "Attribute of `system.build` holding the image";
    };
  };

  formats = {
    iso = { modulesPath, ... }: {
      imports = [ "${modulesPath}/installer/cd-dvd/iso-image.nix" ];
      isoImage.makeEfiBootable = true;
      isoImage.makeUsbBootable = true;
      formatAttr = "isoImage";
    };

    raw-efi = { config, lib, pkgs, modulesPath, ... }: {
      imports = [ "${modulesPath}/virtualisation/disk-size-option.nix" ];

      fileSystems."/" = {
        device = "/dev/disk/by-label/nixos";
        autoResize = true;
        fsType = "ext4";
      };
      fileSystems."/boot" = {
        device = "/dev/disk/by-label/ESP";
        fsType = "vfat";
      };

      boot = {
        growPartition = true;
        kernelParams = [ "console=ttyS0" ];
        loader.grub = {
          device = "nodev";
          efiSupport = true;
          efiInstallAsRemovable = true;
        };
        loader.timeout = lib.mkDefault 0;
        initrd.availableKernelModules = [ "uas" ];
      };

      system.build.raw = import "${modulesPath}/../lib/make-disk-image.nix" {
        inherit lib config pkgs;
        partitionTableType = "efi";
        inherit (config.virtualisation) diskSize;
        format = "raw";
      };
      formatAttr = "raw";
    };
  };
in
{
  nixosGenerate = { format, modules ? [ ], ... } @ args:
    let
      formatModule = formats.${format} or (throw "Unsupported image format '${format}', expected one of: ${builtins.concatStringsSep ", " (builtins.attrNames formats)}");
      image = nixpkgs.lib.nixosSystem (builtins.removeAttrs args [ "format" ] // {
        modules = [ formatAttrOption formatModule ] ++ modules;
      });
    in
    image.config.system.build.${image.config.formatAttr};
}
