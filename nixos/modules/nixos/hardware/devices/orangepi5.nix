{ inputs, config, lib, pkgs, ... }:
{
  imports = [ ./orangepi5-common.nix ];

  config = lib.mkIf (config.bcl.hardware.device == "orangepi5") {

    bcl.disk.ubootPackage = pkgs.ubootOrangePi5;

    hardware.deviceTree = {
      name = "rockchip/rk3588-orangepi-5.dtb";
    };

    boot.initrd.kernelModules = [ "st" ]; # support network at boot
  };
}
