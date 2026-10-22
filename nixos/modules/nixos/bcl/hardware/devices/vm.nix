{ config, lib, pkgs, ... }:

{
  config = lib.mkMerge [
    { bcl.hardware.knownDevices = [ "vm" ]; }
    (lib.mkIf (config.bcl.hardware.device == "vm") {

    hardware.enableRedistributableFirmware = false; # VM do not need firmware

    bcl.hardware.commons = [ "qemu-guest" ];

    boot.initrd.availableKernelModules = [ "xhci_pci" "virtio_pci" "virtio_scsi" "usbhid" "sr_mod" ];
    boot.initrd.kernelModules = [ "virtio" ];

    # serial console for `virsh console` (see the serial/console devices in vm.nix). aarch64 uses the pl011 one
    # advertised by ACPI SPCR, nothing to set there.
    boot.kernelParams = lib.optionals pkgs.stdenv.hostPlatform.isx86_64 [ "console=tty0" "console=ttyS0,115200" ];

    bcl.system.devices = [ "/dev/vda" ];
  })
  ];
}
