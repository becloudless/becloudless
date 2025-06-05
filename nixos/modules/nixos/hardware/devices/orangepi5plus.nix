{ config, lib, pkgs, modulesPath, nixpkgs, ... }:

{
  imports =
    [ (modulesPath + "/installer/scan/not-detected.nix")
    ];

  config = lib.mkIf (config.bcl.hardware.device == "orangepi5plus") {
    bcl.hardware.common = "orangepi";

    boot.initrd.availableKernelModules = [ "nvme" "usbhid" "r8169" ];
    boot.initrd.kernelModules = [ "r8169" ];

    boot.initrd.systemd.tpm2.enable = false; # no TPM on orangepi

    ###########

    hardware.deviceTree = {
      # https://github.com/armbian/build/blob/f9d7117/config/boards/orangepi5-plus.wip#L10C51-L10C51
      name = "rockchip/rk3588-orangepi-5-plus.dtb";
      overlays = [
      ];
    };

    # Both network cards are enabled and cannot be disabled, we have to be explicit
    systemd.network.networks.net.matchConfig = {
      Name = lib.mkForce "enP3p49s0"; # next to power. enP4p65s0 next to hdmi
    };
  };
}
