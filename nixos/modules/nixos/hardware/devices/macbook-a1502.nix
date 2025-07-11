# Do not modify this file!  It was generated by ‘nixos-generate-config’
# and may be overwritten by future invocations.  Please make changes
# to /etc/nixos/configuration.nix instead.
{ config, lib, pkgs, modulesPath, ... }:

{
  imports =
    [ (modulesPath + "/hardware/network/broadcom-43xx.nix")
      (modulesPath + "/installer/scan/not-detected.nix")
    ];


  config = lib.mkIf (config.bcl.hardware.device == "macbook-a1502") {
    bcl.hardware.common = "intel";

    boot.initrd.availableKernelModules = [ "xhci_pci" "ahci" "usb_storage" "usbhid" "sd_mod" ];


    # F1-F12 keys by default
    boot.extraModprobeConfig = ''
      options hid_apple fnmode=2
    '';

      # programs.dconf.profiles.gdm.database = [{
      #   settings."org/gnome/desktop/interface".scaling-factor = lib.gvariant.mkUint32 1;
      # }];

      # home-manager.users.gdm = { lib, ... }: {
      #   dconf.settings = {
      #     "org/gnome/desktop/interface" = {
      #       scaling-factor = lib.hm.gvariant.mkUint32 1;
      #     };
      #   };
      #   home.stateVersion = "23.11";
      # };

  };


}
