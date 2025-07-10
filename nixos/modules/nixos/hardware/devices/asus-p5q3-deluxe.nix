{ config, lib, pkgs, modulesPath, ... }:

{
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
  ];

  config = lib.mkIf (config.bcl.hardware.device == "asus-p5q3-deluxe") {
    bcl.hardware.common = "intel";
    bcl.boot.efi = false;

    boot.initrd.availableKernelModules = [ "uhci_hcd" "ehci_pci" "ahci" "usb_storage" "usbhid" "floppy" "sd_mod" ];
  };
}
