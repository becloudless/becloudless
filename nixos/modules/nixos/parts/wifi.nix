{ config, lib, ... }: let
  cfg = config.bcl.wifi;
in {
  options.bcl.wifi = {
    enable = lib.mkEnableOption "Enable the default settings?";
  };

  config = lib.mkIf cfg.enable {
    networking.wireless.enable = false;
    networking.networkmanager.enable = true;

    # TODO use sops to write NetworkManager connections files
    sops.templates."wifi-SSID" = {
      content = ''
        [connection]
        id=SSID
        type=wifi

        [wifi]
        mode=infrastructure
        ssid=SSID

        [wifi-security]
        key-mgmt=wpa-psk
        psk=PASSWORD

        [ipv4]
        method=auto

        [ipv6]
        addr-gen-mode=default
        method=auto
      '';
      path = "/etc/NetworkManager/system-connections/SSID.nmconnection";
    };
  };
}
