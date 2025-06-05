{ config, lib, pkgs, modulesPath, ... }:

{
  imports =
    [ (modulesPath + "/profiles/qemu-guest.nix")
    ];

  config = lib.mkIf (config.bcl.hardware.device == "ovh-vps") {
    bcl.hardware.common = "intel";
    bcl.boot.uefi = false;

    boot.initrd.availableKernelModules = [ "ata_piix" "uhci_hcd" "virtio_pci" "virtio_scsi" "virtio_blk" ];
    boot.initrd.kernelModules = [ "virtio" ];
  };
}
