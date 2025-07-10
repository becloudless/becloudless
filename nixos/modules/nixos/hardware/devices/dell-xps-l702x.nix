{ config, lib, pkgs, modulesPath, ... }:

{
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
  ];

  config = lib.mkIf (config.bcl.hardware.device == "dell-xps-l702x") {
    bcl.hardware.common = "intel-legacy";
    bcl.boot.efi = false;
    bcl.disk.gpt = false;

    boot.initrd.availableKernelModules = [ "ehci_pci" "ahci" "xhci_pci" "usb_storage" "sd_mod" "sr_mod" ];

    #########################

    hardware.opengl = {
      enable = true;
      extraPackages = with pkgs; [
        mesa
        mesa.drivers
      ];
    };

#    hardware.nvidia = {
#      package = config.boot.kernelPackages.nvidiaPackages.legacy_390; # package is broken
#      prime = {
#        intelBusId = "PCI:0:2:0";
#        nvidiaBusId = "PCI:1:0:0";
#      };
#    };


    boot.extraModprobeConfig = ''
      blacklist nouveau
      options nouveau modeset=0
    '';

    services.udev.extraRules = ''
      # Remove NVIDIA USB xHCI Host Controller devices, if present
      ACTION=="add", SUBSYSTEM=="pci", ATTR{vendor}=="0x10de", ATTR{class}=="0x0c0330", ATTR{power/control}="auto", ATTR{remove}="1"
      # Remove NVIDIA USB Type-C UCSI devices, if present
      ACTION=="add", SUBSYSTEM=="pci", ATTR{vendor}=="0x10de", ATTR{class}=="0x0c8000", ATTR{power/control}="auto", ATTR{remove}="1"
      # Remove NVIDIA Audio devices, if present
      ACTION=="add", SUBSYSTEM=="pci", ATTR{vendor}=="0x10de", ATTR{class}=="0x040300", ATTR{power/control}="auto", ATTR{remove}="1"
      # Remove NVIDIA VGA/3D controller devices
      ACTION=="add", SUBSYSTEM=="pci", ATTR{vendor}=="0x10de", ATTR{class}=="0x03[0-9]*", ATTR{power/control}="auto", ATTR{remove}="1"
    '';
    boot.blacklistedKernelModules = [ "nouveau" "nvidia" "nvidia_uvm" "nvidia_drm" "nvidia_modeset" ];


  };
}
