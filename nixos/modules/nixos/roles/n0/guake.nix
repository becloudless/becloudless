{ config, lib, pkgs, ... }:
{

  config = lib.mkIf (config.bcl.role.name == "n0") {
    home-manager.users.n0rad = { lib, pkgs, ... }: {
      home.file.".config/autostart/guake.desktop".text = ''
        [Desktop Entry]
        Name[fr]=Terminal Guake
        Name=Guake Terminal
        Comment[fxr]=Exploitez la ligne command dans un terminal tel Quake
        TryExec=guake
        Exec=guake
        Icon=guake
        Type=Application
        Categories=GNOME;GTK;System;Utility;TerminalEmulator;
        StartupNotify=true
        X-Desktop-File-Install-Version=0.22
        X-GNOME-Autostart-enabled=true
        Hidden=false
        NoDisplay=false
      '';

      dconf.settings = {
        "apps/guake/general" = {
          restore-tabs-startup = false;
          restore-tabs-notify = false;
          save-tabs-when-changed = false;
          load-guake-yml = false;
          use-popup = false; # popup notification on startup
          use-trayicon = false; # dislay tray icon
          window-refocus = false;
          window-tabbar = false;
          use-scrollbar = false;
          history-size = 10000;
          window-height = 85;
        };
        "apps/guake/keybindings/local" = {
          toggle-fullscreen = "<Shift><Super>x";
        };

        "org/gnome/settings-daemon/plugins/media-keys" = {
          custom-keybindings = ["/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0/"];
        };
        "apps/guake/style/font" = {
          palette-name = "Custom";
          palette = "#000000000000:#cdcb00000000:#0000cdcb0000:#cdcbcdcb0000:#1e1a908fffff:#cdcb0000cdcb:#0000cdcbcdcb:#e5e2e5e2e5e2:#777776767b7b:#ffff00000000:#0000ffff0000:#ffffffff0000:#46458281b4ae:#ffff0000ffff:#0000ffffffff:#ffffffffffff:#ffffffffffff:#000000000000";
        };
        "org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0" = {
          binding = "<Super>x"; # <Super>x
          command = "guake-toggle";
          name = "guake";
        };
      };
    };
  };
}
