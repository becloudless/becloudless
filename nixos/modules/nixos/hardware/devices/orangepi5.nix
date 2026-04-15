{ inputs, config, lib, pkgs, ... }:
{
  imports = [ ./orangepi5-common.nix ];

  config = lib.mkMerge [
    { bcl.hardware.knownDevices = [ "orangepi5" ]; }
    (lib.mkIf (config.bcl.hardware.device == "orangepi5") {
    bcl.hardware.commons = [ "orangepi5-common" ];

    bcl.disk.ubootPackage = lib.mkIf (config.bcl.boot.loader == "uboot") pkgs.ubootOrangePi5;

    hardware.deviceTree = {
      name = "rockchip/rk3588-orangepi-5.dtb";
    };

    boot.initrd.kernelModules = [ "st" ]; # support network at boot
  })
  ];
}
