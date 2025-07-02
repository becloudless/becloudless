{ config, lib, pkgs, modulesPath, ... }:

{
  config = lib.mkIf (config.bcl.hardware.common == "intel") {
    nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
    boot.kernelModules = [ "kvm-intel" ];
    hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;

    hardware.graphics = {
      enable = true;
      enable32Bit = true;
    };
  };
}
