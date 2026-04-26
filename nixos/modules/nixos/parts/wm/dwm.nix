{ config, lib, pkgs, ... }:
let
  dwmUsers = lib.filterAttrs (name: ucfg: ucfg.wm == "dwm") config.bcl.users.users;
in
{

  config = lib.mkIf (dwmUsers != {}) {

    services.unclutter.enable = true; # TODO this is not working

    services.xserver.displayManager.lightdm = {
      enable = true;
      greeter.enable = false;
    };

    services.displayManager = {
  #    enable = true;
      defaultSession = "none+dwm";
    };

    services.xserver = {
      enable = true;
      xkb.layout = "us";

      windowManager.dwm = {
        enable = true;
        package = pkgs.dwm.override {
          patches = [
            ./0001-no-bar-no-border.patch
          ];
        };
      };
    };
  };
}