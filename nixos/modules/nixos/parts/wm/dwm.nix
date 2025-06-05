{ config, lib, pkgs, ... }:
{

  config = lib.mkIf (config.bcl.wm.name == "dwm") {

    services.unclutter.enable = true; # TODO this is not working

    services.xserver.displayManager.lightdm = {
      enable = true;
      greeter.enable = false;
    };

    services.displayManager = {
  #    enable = true;
      defaultSession = "none+dwm";
      autoLogin = {
        enable = true;
        user = config.bcl.wm.user;
      };
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