{ config, lib, ... }:
let
  cfg = config.bcl.bluetooth;
in
{
  options.bcl.bluetooth.enable = lib.mkEnableOption "Enable";


  config = lib.mkIf cfg.enable {

    # Enable Bluetooth
    hardware.bluetooth.enable = true;
    hardware.bluetooth.powerOnBoot = true;
    # services.blueman.enable = true;


    environment.persistence."/nix" = {
      directories = [
        "/var/lib/bluetooth"
      ];
    };

  };
}