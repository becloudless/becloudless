{ config, lib, ... }: let
  cfg = config.bcl.wifi;
  global = config.bcl.global;
  inherit (lib) mkIf mkEnableOption mapAttrsToList concatStringsSep optionalAttrs;

  # Render one NetworkManager connection file from an SSID and password
  mkWifiTemplate = ssid: password: {
    name = "wifi-${ssid}";
    value = {
      content = ''
        [connection]
        id=${ssid}
        type=wifi

        [wifi]
        mode=infrastructure
        ssid=${ssid}

        [wifi-security]
        key-mgmt=wpa-psk
        psk=${password}

        [ipv4]
        method=auto

        [ipv6]
        addr-gen-mode=default
        method=auto
      '';
      path = "/etc/NetworkManager/system-connections/${ssid}.nmconnection";
    };
  };

in {
  options.bcl.wifi = {
    enable = mkEnableOption "Enable the default settings?";
  };

  config = mkIf cfg.enable {
    networking.wireless.enable = false;
    networking.networkmanager.enable = true;

    # Generate one sops template per SSID defined in the SOPS secrets file
    # at bcl.global.secretFile, under `network.wifi.<SSID>`.
    sops = mkIf (global.secretFile != null) {
      defaultSopsFile = global.secretFile;

      # secrets used only as interpolation sources for templates
      secrets = optionalAttrs (config ? sops && config.sops ? secrets) config.sops.secrets // {
        "network.wifi".sopsFile = global.secretFile;
      };

      templates = let
        wifiSecrets = (config.sops.secrets."network.wifi" or {});
      in
        (config.sops.templates or {}) //
        builtins.listToAttrs (
          mapAttrsToList (ssid: _: mkWifiTemplate ssid "${config.sops.placeholder?network.wifi.${ssid}}") wifiSecrets
        );
    };
  };
}
