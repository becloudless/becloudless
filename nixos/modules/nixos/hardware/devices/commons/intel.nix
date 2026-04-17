{ config, lib, pkgs, modulesPath, ... }:

{
  config = lib.mkMerge [
    { bcl.hardware.knownCommons = [ "intel" ]; }
    (lib.mkIf (builtins.elem "intel" config.bcl.hardware.commons) {
      nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
      boot.kernelModules = [ "kvm-intel" ];
      hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;

      hardware.graphics = {
        enable = true;
        enable32Bit = true;
      };
    })
  ];
}
