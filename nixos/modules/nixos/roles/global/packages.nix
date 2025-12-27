{ config, lib, pkgs, ... }:

{
  config = lib.mkIf (config.bcl.role.name != "") {
    environment.systemPackages = with pkgs; [
      bcl.becloudless
      pciutils usbutils
      cryptsetup
      ethtool socat conntrack-tools iputils iproute2
      htop btop iftop lsof dfc psmisc ncdu tree nmon
      rsync tmux
      vim
    ];
  };
}
