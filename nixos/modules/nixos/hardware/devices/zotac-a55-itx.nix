{ config, lib, pkgs, modulesPath, ... }:

{
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
  ];

  config = lib.mkIf (config.bcl.hardware.device == "zotac-a55-itx") {
    bcl.hardware.common = "intel-legacy";
    bcl.boot.efi = false;

    boot.initrd.availableKernelModules = [ "uhci_hcd" "ehci_pci" "ata_piix" "ahci" "usb_storage" "usbhid" "sd_mod" ];
  };
}
