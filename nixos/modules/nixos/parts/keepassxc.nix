{ config, lib, pkgs, ... }:
{
  options.bcl.keepassxc.enable = lib.mkEnableOption "Enable";

  config = lib.mkIf config.bcl.keepassxc.enable  {

    programs.ssh.startAgent = true;

    environment.systemPackages = with pkgs; [
      keepassxc
    ];
  };

}