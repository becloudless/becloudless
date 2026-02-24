{ modulesPath, config, lib, inputs, pkgs, ... }:
let
  rootPartitionUUID = "14e19a7b-0ae0-484d-9d54-43bd6fdc20c7";
  unstable = inputs.nixpkgs-unstable.legacyPackages.${pkgs.system};
  uboot = pkgs.ubootOrangePi5Plus;
in
{
  #  nix build .#nixosConfigurations.install-opi.config.system.build.sdImage
  imports = [ "${modulesPath}/installer/sd-card/sd-image.nix" ];

  boot = {
    kernelPackages = unstable.linuxPackages_latest;
    supportedFilesystems = {
      zfs = lib.mkForce false;
    };

    kernelParams = lib.mkBefore [
      "rootwait"

      "earlycon" # enable early console, so we can see the boot messages via serial port / HDMI
      "consoleblank=0" # disable console blanking(screen saver)
      "console=ttyS2,1500000" # serial port
      "console=tty1" # HDMI

      "root=UUID=${rootPartitionUUID}"
      "rootfstype=ext4"
    ];

    consoleLogLevel = 7;

    loader = {
      grub.enable = lib.mkForce false;
      generic-extlinux-compatible.enable = lib.mkForce true;
    };

  };

  sdImage = {
    inherit rootPartitionUUID;
    compressImage = true;

    # The "firmware" partition is mounted to /boot/firmware/ and used for
    # raspberrypi-specific binary blobs, we don't need it. Our u-boot data will
    # live in the root partition under /boot — this is the default on Nixpkgs.
    populateFirmwareCommands = "";

    # The sd-image.nix has no way to disable firmware partition, so let's just
    # set its size to 1MB. We won't use it.
    firmwareSize = 1; # MiB
    firmwarePartitionName = "DUMMY";

    # Gap in front of the /boot/firmware partition, in mebibytes (1024×1024
    # bytes). That space is needed to fit the idbloader.img and u-boot.itb (see below).
    # The 32MB is extremely generous, the actual binaries below are much smaller.
    firmwarePartitionOffset = 32;

    # This installs the extlinux.conf into /boot, so u-boot finds it and
    # discovers our kernel.
    populateRootCommands = ''
      ${config.boot.loader.generic-extlinux-compatible.populateCmd} -c ${config.system.build.toplevel} -d ./files/boot
    '';

    # Write u-boot code into the 32MB gap
    postBuildCommands = ''
      dd if=${uboot}/idbloader.img of=$img seek=64 conv=fsync,notrunc
      dd if=${uboot}/u-boot.itb of=$img seek=16384 conv=fsync,notrunc
    '';
  };
}
