{ inputs, config, lib, pkgs, ... }:
let
  unstable = inputs.nixpkgs-unstable.legacyPackages.${pkgs.system};
in
{
  config = lib.mkIf (builtins.elem config.bcl.hardware.device [ "orangepi5" "orangepi5plus" ]) {
    bcl.boot.loader = "uboot";

    hardware = {
      firmware = [ unstable.linux-firmware ];
    };

    boot = {
      initrd = {
        systemd.tpm2.enable = false; # no TPM on orangepi
        availableKernelModules = [
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
      };

      # kernel version support. unstable is still required at least till 7.0
      # https://gitlab.collabora.com/hardware-enablement/rockchip-3588/notes-for-rockchip-3588/-/blob/main/mainline-status.md
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
