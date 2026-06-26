{ config, lib, pkgs, ... }:
let
  xfceUsers = lib.filterAttrs (name: ucfg: ucfg.wm.name == "xfce") config.bcl.users.users;
in
{
  config = lib.mkIf (xfceUsers != {}) {
    services.xserver.desktopManager.xfce.enable = true;
  };
}
