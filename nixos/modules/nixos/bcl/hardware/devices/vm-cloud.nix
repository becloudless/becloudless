{ config, lib, ... }:

{
  config = lib.mkMerge [
    { bcl.hardware.knownDevices = [ "vm-cloud" ]; }
    (lib.mkIf (config.bcl.hardware.device == "vm-cloud") {

      hardware.enableRedistributableFirmware = false; # VM do not need firmware

      # the virtio drivers (net, pci, blk, scsi) of the initrd: without them the initrd has neither the network (SSH to
      # unlock the disk) nor the disk
      bcl.hardware.commons = [ "qemu-guest" ];

      bcl.boot.loader = "bios";

      boot.initrd.availableKernelModules = [ "ata_piix" "uhci_hcd" ];
      boot.initrd.kernelModules = [ "virtio" ];

      bcl.system.devices = lib.mkDefault [ "/dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_drive-scsi0-0-0-0" ];
    })
  ];
}
