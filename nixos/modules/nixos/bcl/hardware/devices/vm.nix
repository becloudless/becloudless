{ config, lib, ... }:

{
  config = lib.mkMerge [
    { bcl.hardware.knownDevices = [ "vm" ]; }
    (lib.mkIf (config.bcl.hardware.device == "vm") {

    hardware.enableRedistributableFirmware = false; # VM do not need firmware

    bcl.hardware.commons = [ "qemu-guest" ];

    boot.initrd.availableKernelModules = [ "xhci_pci" "virtio_pci" "virtio_scsi" "usbhid" "sr_mod" ];
    boot.initrd.kernelModules = [ "virtio" ];

    bcl.system.devices = [ "/dev/vda" ];
  })
  ];
}
