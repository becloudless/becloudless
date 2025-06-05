{ config, lib, pkgs, ... }:

{
  config = lib.mkIf config.bcl.role.enable {
    environment.systemPackages = with pkgs; [
      pciutils usbutils
      cryptsetup
      ethtool socat conntrack-tools iputils iproute2
      htop iftop lsof dfc psmisc ncdu tree nmon
      rsync tmux
      vim
    ];
  };
}
