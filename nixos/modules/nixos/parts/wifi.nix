{ config, lib, ... }: let
  cfg = config.bcl.wifi;
in {
  options.bcl.wifi = {
    enable = lib.mkEnableOption "Enable the default settings?";
  };

  config = lib.mkIf cfg.enable {
    networking.wireless.enable = false;
    networking.networkmanager.enable = true;

    sops.secrets."networking.networkmanager.profiles.bcl" = {
      sopsFile = ../secrets.yaml;
      path = "/etc/NetworkManager/system-connections/bcl.nmconnection";
    };

  };
}
