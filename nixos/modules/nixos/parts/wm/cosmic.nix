{ config, lib, pkgs, ... }:

let
  cosmicUsers = lib.filterAttrs (name: ucfg: ucfg.wm == "cosmic") config.bcl.users;
in
{
  config = lib.mkIf (cosmicUsers != {}) {
    services.displayManager.cosmic-greeter.enable = true;
    services.desktopManager.cosmic.enable = true;
    services.system76-scheduler.enable = true;

    programs.firefox.preferences = {
        # disable libadwaita theming for Firefox
        "widget.gtk.libadwaita-colors.enabled" = false;
      };
  };
}
