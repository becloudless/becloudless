{ config, lib, pkgs, ... }:
{
  config = lib.mkIf (config.bcl.role.name != "") {

    programs.ssh.startAgent = true;

    environment.systemPackages = with pkgs; [
      keepassxc
    ];
  };

}