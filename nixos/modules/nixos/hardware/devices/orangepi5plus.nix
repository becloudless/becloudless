 { inputs, config, lib, pkgs, ... }:
 let
   unstable = inputs.nixpkgs-unstable.legacyPackages.${pkgs.system};
 in
 {
  config = lib.mkIf (config.bcl.hardware.device == "orangepi5plus") {

    bcl.boot.loader = "uboot";
    bcl.disk.uBootPackage = pkgs.ubootOrangePi5Plus;

    hardware = {
      firmware = [ unstable.linux-firmware ];
      deviceTree = {
        name = "rockchip/rk3588-orangepi-5-plus.dtb";
      };
    };

    # Both network cards are enabled and cannot be disabled, we have to be explicit
    systemd.network.networks.net.matchConfig = {
      Name = lib.mkForce "enP3p49s0"; # next to power. enP4p65s0 next to hdmi
    };

    boot = {
      initrd = {
        kernelModules = [ "r8169" ]; # support network at boot
        systemd.tpm2.enable = false; # no TPM on orangepi
        availableKernelModules = [
          # NVMe
          "nvme"

          # SD cards and internal eMMC drives.
          "mmc_block"
          "usbhid"
          "r8169"

          # Support USB keyboards, in case the boot fails and we only have
          # a USB keyboard, or for LUKS passphrase prompt.
          "hid"

          # For LUKS encrypted root partition.
          # https://github.com/NixOS/nixpkgs/blob/nixos-23.11/nixos/modules/system/boot/luksroot.nix#L985
          "dm_mod" # for LVM & LUKS
          "dm_crypt" # for LUKS
          "input_leds"
        ];
      };
      kernelPackages = unstable.linuxPackages_latest;
      kernelParams = [
        "rootwait"

        "earlycon" # enable early console, so we can see the boot messages via serial port / HDMI
        "consoleblank=0" # disable console blanking(screen saver)
        "console=ttyS2,1500000" # serial port
        "console=tty1" # HDMI
      ];
    };
  };
}
