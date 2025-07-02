{ config, lib, pkgs, modulesPath, ... }:

{
  imports = [ (modulesPath + "/installer/scan/not-detected.nix") ];

  config = lib.mkIf (config.bcl.hardware.device == "msi-z590-gaming-plus") {
    bcl.hardware.common = "intel";

    boot.initrd.availableKernelModules = [ "xhci_pci" "ahci" "usbhid" "usb_storage" "sd_mod" ];
  };

}
