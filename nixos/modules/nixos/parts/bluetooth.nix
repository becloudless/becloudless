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


#   config.system.activationScripts.bluetooth = lib.stringAfter [ "var" ] ''
#     mkdir -p /var/lib/bluetooth/A0:99:9B:02:69:AC/cache
#     cat > /var/lib/bluetooth/A0:99:9B:02:69:AC/settings <<EOL
#     [General]
#     Discoverable=false
#     EOL

#     mkdir /var/lib/bluetooth/A0:99:9B:02:69:AC/F4:4E:FD:D9:01:C0
#     touch /var/lib/bluetooth/A0:99:9B:02:69:AC/F4:4E:FD:D9:01:C0/attributes
#     cat > /var/lib/bluetooth/A0:99:9B:02:69:AC/F4:4E:FD:D9:01:C0/info <<EOL
#     [General]
#     Name=Fosi Audio BT30D
#     Class=0x240404
#     SupportedTechnologies=BR/EDR;
#     Trusted=true
#     Blocked=false
#     Services=0000110b-0000-1000-8000-00805f9b34fb;0000110e-0000-1000-8000-00805f9b34fb;00001200-0000-1000-8000-00805f9b34fb;

#     [DeviceID]
#     Source=2
#     Vendor=4310
#     Product=45065
#     Version=256

#     [LinkKey]
#     Key=BDC490180F09E9910F151520842DA996
#     Type=4
#     PINLength=0
#     EOL

#     cat > /var/lib/bluetooth/A0:99:9B:02:69:AC/cache/F4:4E:FD:D9:01:C0 <<EOL
#     [General]
#     Name=Fosi Audio BT30D

#     [ServiceRecords]
#     0x00010000=35380900000A00010000090001350319110B0900043510350619010009001935061900190901030900093508350619110D090103090311090001
#     0x00010001=353B0900000A00010001090001350619110E19110F0900043510350619010009001735061900170901040900093508350619110E090106090311090001
#     0x00010002=356F0900000A000100020900013503191200090004350D35061901000900013503190001090006350909656E09006A09010009000935083506191200090100090100250A506E50205365727665720902000901030902010910D609020209B0090902030901000902042801090205090002

#     [Endpoints]
#     02=01:00:01:ffff0235
#     01=01:00:01:ffff0235
#     LastUsed=09:02
#     EOL


#     find /var/lib/bluetooth/ -type d -exec chmod 700 {} \;
#     find /var/lib/bluetooth/ -type f -exec chmod 600 {} \;
#   '';
}