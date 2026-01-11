{ config, lib, pkgs, ... }:
{
  config = lib.mkIf (config.bcl.role.name == "install") {
    bcl.wifi.enable = true;
    environment.systemPackages = with pkgs; [
      nixos-facter
    ];
  };
}
