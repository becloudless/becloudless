{ inputs, config, lib, pkgs, ... }:
let
  unstable = inputs.nixpkgs-unstable.legacyPackages.${pkgs.system};
in
{
  config = lib.mkIf (config.bcl.role.name != "") {
    environment.systemPackages = with pkgs; [
      bcl.bcl
      pciutils usbutils
      cryptsetup
      ethtool socat conntrack-tools iputils iproute2
      htop btop iftop lsof dfc psmisc ncdu tree nmon
      rsync tmux
      vim
    ];
  };
}
