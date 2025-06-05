{ config, lib, pkgs, modulesPath, ... }:

{
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
  ];


  config = lib.mkIf (config.bcl.hardware.device == "nuc") {
    bcl.hardware.common = "intel-legacy";

    boot.initrd.availableKernelModules = [ "ehci_pci" "ahci" "usbhid" "usb_storage" "sd_mod" ];
  };

}
