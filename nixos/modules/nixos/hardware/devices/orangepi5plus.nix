{ inputs, config, lib, pkgs, ... }:
{
  imports = [ ./orangepi5-common.nix ];

  config = lib.mkIf (config.bcl.hardware.device == "orangepi5plus") {
    bcl.hardware.commons = [ "orangepi5-common" ];

    bcl.disk.ubootPackage = lib.mkIf (config.bcl.boot.loader == "uboot") pkgs.ubootOrangePi5Plus;

    hardware.deviceTree = {
      name = "rockchip/rk3588-orangepi-5-plus.dtb";
    };

    # Both network cards are enabled and cannot be disabled, we have to be explicit
    systemd.network.networks.net.matchConfig = {
      Name = lib.mkForce "enP3p49s0"; # next to power. enP4p65s0 next to hdmi
    };

    boot.initrd = {
      kernelModules = [ "r8169" ]; # support network at boot
      availableKernelModules = [
        "usbhid"
        "r8169"
      ];
    };
  };
}
