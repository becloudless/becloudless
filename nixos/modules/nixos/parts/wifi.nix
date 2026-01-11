{ config, lib, ... }: let
  cfg = config.bcl.wifi;
  global = config.bcl.global;
  inherit (lib) mkIf mkEnableOption;

  # helper to build one template for one SSID
  mkWifiTemplate = ssid: {
    content = ''
      [connection]
      id=${ssid}
      type=wifi

      [wifi]
      mode=infrastructure
      ssid=${ssid}

      [wifi-security]
      key-mgmt=wpa-psk
      psk={{ .network.wifi.${ssid} }}

      [ipv4]
      method=auto

      [ipv6]
      addr-gen-mode=default
      method=auto
    '';
    path = "/etc/NetworkManager/system-connections/${ssid}.nmconnection";
  };

in {
  options.bcl.wifi = {
    enable = mkEnableOption "Enable the default settings?";
    ssids = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = "List of WiFi SSIDs for which to generate NetworkManager connections";
    };
  };

  config = mkIf cfg.enable {
    networking.wireless.enable = false;
    networking.networkmanager.enable = true;

    # Expose `network.wifi` subtree from the SOPS file so templates can use
    # `{{ .network.wifi.<SSID> }}` as the PSK.
    sops = mkIf (global.secretFile != null) {
      defaultSopsFile = global.secretFile;

      secrets."network.wifi".sopsFile = global.secretFile;

      templates = lib.listToAttrs (map (ssid: {
        name = "wifi-${ssid}";
        value = mkWifiTemplate ssid;
      }) cfg.ssids);
    };
  };
}
