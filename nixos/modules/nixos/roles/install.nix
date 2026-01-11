{ config, lib, pkgs, ... }:
{
  config = lib.mkIf (config.bcl.role.name == "install") {
    environment.systemPackages = with pkgs; [
      nixos-facter
    ];
  };
}