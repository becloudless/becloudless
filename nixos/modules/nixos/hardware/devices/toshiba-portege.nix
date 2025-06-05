{ config, lib, pkgs, modulesPath, ... }:

{
  imports =
    [ (modulesPath + "/installer/scan/not-detected.nix")
    ];

  config = lib.mkIf (config.bcl.hardware.device == "toshiba-portege") {
    bcl.hardware.common = "intel";
    bcl.boot.uefi = false;

    boot.initrd.availableKernelModules = [ "ehci_pci" "ahci" "usb_storage" "sd_mod" "sdhci_pci" ];
  };

}
