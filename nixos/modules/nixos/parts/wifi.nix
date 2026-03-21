{ config, lib, ... }: let
  cfg = config.bcl.wifi;
  global = config.bcl.global;
  inherit (lib) mkIf mkEnableOption;

  # Extract SSIDs from the sops secret file keys at eval time.
  # Keys are stored in plaintext in the SOPS YAML even when values are encrypted.
  # Expected key format: networking.wireless.<ssid>.password
  ssidsFromFile =
    if global.secretFile == null then []
    else
      let
        lines = lib.splitString "\n" (builtins.readFile global.secretFile);
        prefix = "networking.wireless.";
        extractSsid = line:
          if lib.hasPrefix prefix line
          then
            let
              withoutPrefix = lib.removePrefix prefix line;
              parts = lib.splitString "." withoutPrefix;
            in
              # parts = [ "<ssid>" "password:" ... ] — need at least 2 elements
              # and the second element must start with "password:"
              if lib.length parts >= 2 && lib.hasPrefix "password:" (lib.elemAt parts 1)
              then lib.head parts
              else null
          else null;
      in lib.filter (s: s != null) (map extractSsid lines);

  # Merge SSIDs from the secret file and the explicit option, deduplicating
  wirelessSsids = lib.unique (ssidsFromFile ++ global.networking.wireless);

in {
  options.bcl.wifi = {
    enable = mkEnableOption "Enable wifi management via NetworkManager";
  };

  config = mkIf cfg.enable {
    networking.wireless.enable = false;
    networking.networkmanager.enable = true;

    # Declare SOPS secrets for wifi passwords derived from keys in the secret file
    sops.secrets = mkIf (global.secretFile != null && wirelessSsids != []) (
      lib.listToAttrs (map (ssid: {
        name = "networking.wireless.${ssid}.password";
        value = {
          sopsFile = global.secretFile;
        };
      }) wirelessSsids)
    );

    # Generate NetworkManager connection profiles using sops.templates
    sops.templates = mkIf (global.secretFile != null && wirelessSsids != []) (
      lib.listToAttrs (map (ssid: {
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
            psk=${config.sops.placeholder."networking.wireless.${ssid}.password"}

            [ipv4]
            method=auto

            [ipv6]
            method=auto
          '';
        };
      }) wirelessSsids)
    );
  };
}
