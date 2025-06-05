{ config, lib, pkgs, ... }:
{
  config = lib.mkIf (config.bcl.wm.name == "pantheon") {
    services.xserver.desktopManager.pantheon.enable = true;

    # pantheon greeter does not respect keyboard layout
    services.xserver.displayManager.lightdm.greeters.pantheon.enable = false;
    services.xserver.displayManager.lightdm.greeters.gtk.enable = true;

    home-manager.users."${config.bcl.wm.user}" = { lib, pkgs, ... }: {
      dconf.settings = with lib.hm.gvariant; {
        "net/launchpad/plank/docks/dock1" = {
           dock-items = [
            "gala-multitaskingview.dockitem"
            "io.elementary.files.dockitem"
            "firefox.dockitem"
            "io.elementary.mail.dockitem"
            "io.elementary.tasks.dockitem"
            "io.elementary.calendar.dockitem"
            "io.elementary.music.dockitem"
            "io.elementary.videos.dockitem"
            "io.elementary.photos.dockitem"
            "io.elementary.switchboard.dockitem"
          ];
        };

        "org/gnome/desktop/background" = {
          picture-uri = "file:///run/current-system/sw/share/backgrounds/Tj%20Holowaychuk.jpg";
        };

        "org/gnome/desktop/interface" = {
          gtk-theme = "io.elementary.stylesheet.blueberry";
        };

      };
    };
  };
}
