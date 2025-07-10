{ config, lib, pkgs, modulesPath, ... }:

{
  imports =
    [ (modulesPath + "/profiles/qemu-guest.nix")
    ];

  config = lib.mkIf (config.bcl.hardware.device == "infomaniak-vps") {
    bcl.hardware.common = "intel";
    bcl.boot.efi = false;

    boot.initrd.availableKernelModules = [ "ata_piix" "uhci_hcd" "virtio_pci" "virtio_scsi" "sd_mod" "sr_mod" ];
    boot.initrd.kernelModules = [ "virtio" ];
  };
}
