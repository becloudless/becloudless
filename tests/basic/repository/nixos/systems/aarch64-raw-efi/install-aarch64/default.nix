{ modulesPath, ... }:
let
  unstable = inputs.nixpkgs-unstable.legacyPackages.${pkgs.system};
in
{
  imports = [ "${modulesPath}/installer/cd-dvd/installation-cd-minimal.nix" ];
  bcl.role.name = "install";

  boot.kernelPackages = unstable.linuxPackages_latest;

  boot.kernelParams = [
    "rootwait"

    "earlycon" # enable early console, so we can see the boot messages via serial port / HDMI
    "consoleblank=0" # disable console blanking(screen saver)
    "console=ttyS2,1500000" # serial port
    "console=tty1" # HDMI
  ];

  boot.initrd.availableKernelModules = [
    # NVMe
    "nvme"

    # SD cards and internal eMMC drives.
    "mmc_block"

    # Support USB keyboards, in case the boot fails and we only have
    # a USB keyboard, or for LUKS passphrase prompt.
    "hid"

    # For LUKS encrypted root partition.
    # https://github.com/NixOS/nixpkgs/blob/nixos-23.11/nixos/modules/system/boot/luksroot.nix#L985
    "dm_mod" # for LVM & LUKS
    "dm_crypt" # for LUKS
    "input_leds"
  ];

  hardware.deviceTree = {
    name = "rockchip/rk3588-orangepi-5-plus.dtb";
  };
}
