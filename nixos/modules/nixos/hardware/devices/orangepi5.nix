{ config, lib, pkgs, modulesPath, ... }:
{
  imports =
    [ (modulesPath + "/installer/scan/not-detected.nix")
    ];

  config = lib.mkIf (config.bcl.hardware.device == "orangepi5") {
    bcl.hardware.common = "orangepi";

    boot.initrd.availableKernelModules = [ "usb_storage" ];
    boot.initrd.kernelModules = [ "st" ];

    ###########

    #    https://github.com/armbian/linux-rockchip/blob/rk-5.10-rkr4/arch/arm64/boot/dts/rockchip/rk3588s-orangepi-5.dts
    hardware.deviceTree = {
      name = "rockchip/rk3588s-orangepi-5.dtb";
      overlays = [];
    };
  };
}
