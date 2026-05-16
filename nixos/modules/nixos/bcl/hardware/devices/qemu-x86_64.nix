{ config, lib, pkgs, modulesPath, ... }:

{
  config = lib.mkMerge [
    { bcl.hardware.knownDevices = [ "qemu-x86_64" ]; }
    (lib.mkIf (config.bcl.hardware.device == "qemu-x86_64") {

    hardware.enableRedistributableFirmware = false; # VM do not need firmware

    bcl.hardware.commons = [ "qemu-guest" ];
    bcl.boot.loader = "bios";

    boot.initrd.availableKernelModules = [ "ata_piix" "ohci_pci" "ehci_pci" "ahci" "sd_mod" "sr_mod" "e1000e"  "e1000" ];
    boot.initrd.kernelModules = [ "e1000" ];
  })
  ];
}
