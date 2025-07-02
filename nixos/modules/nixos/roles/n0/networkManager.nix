
{ config, lib, pkgs, ... }: {

  config = lib.mkIf (config.bcl.role.name == "n0") {
    networking.wireless.enable = false;
    networking.networkmanager.enable = true;

    sops.secrets."networking.networkmanager.profiles.n0p1" = {
      sopsFile = ../n0.secrets.yaml;
      path = "/etc/NetworkManager/system-connections/n0p1.nmconnection";
    };
    sops.secrets."networking.networkmanager.profiles.FunAndSeriousParis" = {
      sopsFile = ../n0.secrets.yaml;
      path = "/etc/NetworkManager/system-connections/FunAndSeriousParis.nmconnection";
    };
    sops.secrets."networking.networkmanager.profiles.FlatItalien" = {
      sopsFile = ../n0.secrets.yaml;
      path = "/etc/NetworkManager/system-connections/FlatItalien.nmconnection";
    };
    sops.secrets."networking.networkmanager.profiles.Starlink-Baladins" = {
      sopsFile = ../n0.secrets.yaml;
      path = "/etc/NetworkManager/system-connections/Starlink-Baladins.nmconnection";
    };
    sops.secrets."networking.networkmanager.profiles.mvl_home" = {
      sopsFile = ../n0.secrets.yaml;
      path = "/etc/NetworkManager/system-connections/mvl_home.nmconnection";
    };
  };
}
