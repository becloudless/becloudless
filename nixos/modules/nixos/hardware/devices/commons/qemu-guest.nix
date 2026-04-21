{ config, lib, pkgs, modulesPath, ... }:

{
  # from https://github.com/NixOS/nixpkgs/blob/master/nixos/modules/installer/scan/not-detected.nix
  config = lib.mkMerge [
    { bcl.hardware.knownCommons = [ "qemu-guest" ]; }
    (lib.mkIf (builtins.elem "qemu-guest" config.bcl.hardware.commons) {

    boot.initrd.availableKernelModules = [
        "virtio_net"
        "virtio_pci"
        "virtio_mmio"
        "virtio_blk"
        "virtio_scsi"
        "9p"
        "9pnet_virtio"
      ];
      boot.initrd.kernelModules = [
        "virtio_balloon"
        "virtio_console"
        "virtio_rng"
        "virtio_gpu"
      ];

    })
  ];
}
