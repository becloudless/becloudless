{ config, lib, ... }: let
  cfg = config.bcl.wifi;
  global = config.bcl.global;
  inherit (lib) mkIf mkEnableOption mkOption types mapAttrs';

in {
  options.bcl.wifi = {
    enable = mkEnableOption "Enable wifi management via NetworkManager";
  };

  config = mkIf cfg.enable {
    networking.wireless.enable = false;
    networking.networkmanager.enable = true;

    # Declare SOPS secrets for wifi passwords if a global secretFile is provided
    sops.secrets = mkIf (global.secretFile != null && (global.networking.wireless or {} != {})) (
      mapAttrs' (ssid: _: {
        name = "networking.wireless.${ssid}.password";
        value = {
          sopsFile = global.secretFile;
        };
      }) global.networking.wireless
    );

    # Generate NetworkManager connection profiles using sops.templates so the
    # password comes from the decrypted SOPS secret
    sops.templates = mkIf (global.secretFile != null && (global.networking.wireless or {} != {})) (
      mapAttrs' (ssid: _: {
        name = "NetworkManager/system-connections/${ssid}.nmconnection";
        value = {
          owner = "root";
          group = "root";
          mode = "0400";
          path = "/etc/NetworkManager/system-connections/${ssid}.nmconnection";
          content = ''
            [connection]
            id=${ssid}
            type=wifi

            [wifi]
            mode=infrastructure
            ssid=${ssid}

            [wifi-security]
            key-mgmt=wpa-psk
            psk={{ ."networking.wireless.${ssid}.password" }}

            [ipv4]
            method=auto

            [ipv6]
            method=auto
          '';
        };
      }) global.networking.wireless
    );
  };
}
