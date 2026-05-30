{ config, lib, pkgs, ... }:

let
  gnomeUsers = lib.filterAttrs (name: ucfg: ucfg.wm.name == "gnome") config.bcl.users.users;
in
{
  config = lib.mkIf (gnomeUsers != {}) {

    services.xserver = {
      enable = true;
    };

    # Enable the GNOME Desktop Environment.
    services.displayManager.gdm.enable = true;
    services.desktopManager.gnome.enable = true;

    # so keepassxc can do the keyring
    services.gnome.gnome-keyring.enable = lib.mkForce false;
    services.gnome.gnome-browser-connector.enable = true;

    environment.systemPackages = with pkgs; [
      gnome-tweaks dconf-editor
      gjs # required by live-lock-screen extension (spawns gjs subprocess for video player)
      gst_all_1.gst-plugins-rs # gtk4paintablesink for live-lock-screen extension
      gst_all_1.gst-plugins-good
      gst_all_1.gst-plugins-bad
      gst_all_1.gst-plugins-ugly
    ];

    # Make gtk4paintablesink (from gst-plugins-rs) discoverable by GNOME Shell
    # Use GST_PLUGIN_PATH to append without replacing the system path set by NixOS
    environment.variables.GST_PLUGIN_PATH = lib.makeSearchPathOutput "lib" "lib/gstreamer-1.0" (with pkgs.gst_all_1; [
      gst-plugins-rs
      gst-plugins-bad
      gst-plugins-ugly
    ]);

    environment.gnome.excludePackages = (with pkgs; [
      # gnome-photos
      gnome-tour
    ]) ++ (with pkgs; [
      # cheese # webcam tool
      # gnome-music
      # gedit # text editor
      # epiphany # web browser3 years ago
      gnome-initial-setup
    ]);

    systemd.user.services."restore-windows" = {
      enable = true;
      path = with pkgs; [
        bash
        dconf
      ];
      script = ''
        dconfPath="/org/gnome/shell/extensions/smart-auto-move/saved-windows"
        filePath=/nix/home/$USER/Home/home/$USER/.config/saved-windows
        content="[/]\nsaved-windows=$(cat $filePath)"

      '';
      after = [ "graphical-session-pre.target" ];
      partOf = [ "graphical-session.target" ];
      wantedBy = [ "graphical-session.target" ];
    };

    systemd.user.services."saved-windows" = {
      enable = true;
      path = with pkgs; [
        bash
        dconf
      ];
      script = ''
        dconfPath=/org/gnome/shell/extensions/SmartAutoMoveNG/saved-windows
        filePath=/nix/home/$USER/.config/saved-windows

        cat $filePath | ${pkgs.dconf}/bin/dconf load /org/gnome/shell/extensions/SmartAutoMoveNG/ || true

        ${pkgs.dconf}/bin/dconf watch $dconfPath | while read line; do
          if [ "$line" = "$dconfPath" ]; then
            continue
          fi
          if [ "$line" = "" ]; then
            continue
          fi
          ${pkgs.dconf}/bin/dconf dump /org/gnome/shell/extensions/SmartAutoMoveNG/ > $filePath
        done
      '';
      after = [ "graphical-session-pre.target" ];
      partOf = [ "graphical-session.target" ];
      wantedBy = [ "graphical-session.target" ];
    };

    home-manager.users = lib.mapAttrs (name: ucfg:
      let liveLockScreen = pkgs.bcl.live-lock-screen; in
      { lib, pkgs, ... }: {

      home.packages = with pkgs; [
        gnomeExtensions.dash-to-panel
        gnomeExtensions.weather-oclock
        gnomeExtensions.system-monitor-next
        gnomeExtensions.workspace-matrix
        gnomeExtensions.workspace-indicator
        gnomeExtensions.wallpaper-slideshow
        gnomeExtensions.quake-terminal
        gnomeExtensions.smart-auto-move-ng
        gnomeExtensions.no-overview
        liveLockScreen
      ];

      # dconf watch /
      dconf.settings = with lib.hm.gvariant; {
        "org/nemo/window-state" = {
          side-pane-view = "tree";
          sidebar-width = 281;
        };
        "org/nemo/preferences" = {
          default-folder-viewer = "list-view";
        };

        "org/gnome/settings-daemon/plugins/media-keys" = {
          mic-mute = ["<Super>m" "<Super>slash"];
          volume-down = ["<Super>comma"];
          volume-up = ["<Super>period"];
          # volume-mute = ["<Super>slash"];

          previous = ["<Super>k"];
          play = ["<Super>l"];
          next = ["<Super>semicolon"];
          # next = ["<Super>apostrophe"];
          screensaver = ["<Control><Alt>l"];
        };

        "org/gnome/desktop/wm/keybindings" = {
          show-screenshot-ui = ["<Control>Home"];
          screenshot-window =  ["<Shift><Control>Home"];

          # move-to-monitor-down = ["<Super>Down"];
          # move-to-monitor-up = ["<Super>Up"];
          # move-to-monitor-left = ["<Super>Left"];
          # move-to-monitor-right = ["<Super>Right"];
        };

        "system/locale/region" = {
          region = "fr_FR.UTF-8";
        };

        "org/gnome/desktop/input-sources" = {
          sources = [ (mkTuple [ "xkb" "fr+us"]) ];
          xkb-options = ["terminate:ctcorbrl_alt_bksp" "lv3:ralt_switch" "ctrl:nocaps"];
        };

        "org/gnome/shell/extensions/azwallpaper" = {
          slideshow-directory = "/home/${name}/Pictures/Wallpapers/3840x2160";
          slideshow-slide-duration = mkTuple [ 4 0 0 ];
        };


        "org/gnome/shell/weather" = {
          locations = [
            (mkVariant (mkTuple [
              (mkUint32 2)
              (mkVariant (mkTuple [
                "Paris-Orly"
                "LFPO"
                false
                [ (mkTuple [ (mkDouble 0.85055711632080566) (mkDouble 0.041887902047863905) ]) ]
                [ (mkTuple [ (mkDouble 0.85055711632080566) (mkDouble 0.041887902047863905) ]) ]
              ]))
            ]))
          ];
        };
        "org/gnome/Weather" = {
          locations = [
            (mkVariant (mkTuple [
              (mkUint32 2)
              (mkVariant (mkTuple [
                "Paris-Orly"
                "LFPO"
                false
                [ (mkTuple [ (mkDouble 0.85055711632080566) (mkDouble 0.041887902047863905) ]) ]
                [ (mkTuple [ (mkDouble 0.85055711632080566) (mkDouble 0.041887902047863905) ]) ]
              ]))
            ]))
          ];
        };
        "org/gnome/GWeather4" = {
          temperature-unit = "centigrade";
        };

        "org/gnome/desktop/peripherals/touchpad" = {
          speed = 0.62790697674418605;
          tap-to-click = true;
          natural-scroll = false;
        };
        "org/gnome/settings-daemon/plugins/color" = {
          night-light-enabled = ucfg.wm.gnome.nightLight.enable;
          night-light-temperature = mkUint32 ucfg.wm.gnome.nightLight.temperature;
        };
        "org/gnome/settings-daemon/plugins/power" = {
          power-button-action = "nothing";
          sleep-inactive-battery-timeout = 1800;
          sleep-inactive-ac-type = "nothing";
        };
        "org/gnome/settings-daemon/plugins/housekeeping" = {
          donation-reminder-last-shown = mkInt64 9223372036854775807;
        };
        "org/gnome/desktop/interface" = {
          color-scheme = "prefer-dark";
          enable-hot-corners = false;
          show-battery-percentage = true;
          clock-show-weekday = true;
        };
        "org/gnome/desktop/wm/preferences" = {
          workspace-names = [ "Main" ];
          num-workspaces = ucfg.wm.gnome.numWorkspaces;
          action-middle-click-titlebar = "lower";
          button-layout = "appmenu:minimize,maximize,close";
        };
        "org/gnome/desktop/notifications" = {
          show-in-lock-screen = false;
        };
        "org/gnome/desktop/search-providers" = {
          disable-external = true;
        };
        "org/gnome/mutter" = {
          edge-tiling = true;
          workspaces-only-on-primary = false;
          dynamic-workspaces = false;
        };
        "org/gnome/shell/app-switcher" = {
          current-workspace-only = true;
        };
        "org/gnome/desktop/session" = {
          idle-delay = 900;
        };
        "org/gnome/desktop/input-sources" = {
          show-all-sources = true;
        };
        "org/gnome/desktop/screensaver" = {
          lock-delay = 30;
        };
        "org/gnome/shell/extensions/system-monitor-next-applet" = {
          icon-display = false;
          cpu-show-text = false;
          cpu-graph-width = 70;
          cpu-refresh-time = 2000;
          memory-show-text = false;
          memory-graph-width = 70;
          memory-refresh-time = 5000;
          swap-display = true;
          swap-show-text = false;
          swap-graph-width = 70;
          swap-refresh-time = 10000;
          net-show-text = false;
          net-graph-width = 70;
          net-refresh-time = 2000;
          disk-display = true;
          disk-graph-width = 70;
          disk-show-text = false;
          disk-refresh-time = 2000;
        };
        "org/gnome/shell/extensions/dash-to-panel" = {
          extension-version = (builtins.fromJSON (builtins.readFile "${pkgs.gnomeExtensions.dash-to-panel}/share/gnome-shell/extensions/dash-to-panel@jderose9.github.com/metadata.json")).version;
          panel-positions = ''{"0":"TOP","1":"TOP","2":"TOP","3":"TOP"}'';
          panel-sizes = ''{"0":24,"1":24,"2":24,"3":24}'';
          appicon-margin = 4;
          appicon-padding = 0;
          dot-size = 0;
          show-favorites = false;
          group-apps = false;
          group-apps-use-fixed-width = false;
          isolate-workspaces = true;
          hide-overview-on-startup = true;
          scroll-panel-action =  "CYCLE_WINDOWS";
          show-window-previews = false;
          panel-element-positions = ''{"0":[{"element":"showAppsButton","visible":false,"position":"stackedTL"},{"element":"activitiesButton","visible":false,"position":"stackedTL"},{"element":"leftBox","visible":true,"position":"stackedTL"},{"element":"taskbar","visible":true,"position":"stackedTL"},{"element":"centerBox","visible":true,"position":"stackedBR"},{"element":"rightBox","visible":true,"position":"stackedBR"},{"element":"dateMenu","visible":true,"position":"stackedBR"},{"element":"systemMenu","visible":true,"position":"stackedBR"},{"element":"desktopButton","visible":false,"position":"stackedBR"}],"1":[{"element":"showAppsButton","visible":false,"position":"stackedTL"},{"element":"activitiesButton","visible":false,"position":"stackedTL"},{"element":"leftBox","visible":true,"position":"stackedTL"},{"element":"taskbar","visible":true,"position":"stackedTL"},{"element":"centerBox","visible":true,"position":"stackedBR"},{"element":"rightBox","visible":true,"position":"stackedBR"},{"element":"dateMenu","visible":true,"position":"stackedBR"},{"element":"systemMenu","visible":true,"position":"stackedBR"},{"element":"desktopButton","visible":false,"position":"stackedBR"}],"2":[{"element":"showAppsButton","visible":false,"position":"stackedTL"},{"element":"activitiesButton","visible":false,"position":"stackedTL"},{"element":"leftBox","visible":true,"position":"stackedTL"},{"element":"taskbar","visible":true,"position":"stackedTL"},{"element":"centerBox","visible":true,"position":"stackedBR"},{"element":"rightBox","visible":true,"position":"stackedBR"},{"element":"dateMenu","visible":true,"position":"stackedBR"},{"element":"systemMenu","visible":true,"position":"stackedBR"},{"element":"desktopButton","visible":false,"position":"stackedBR"}],"3":[{"element":"showAppsButton","visible":false,"position":"stackedTL"},{"element":"activitiesButton","visible":false,"position":"stackedTL"},{"element":"leftBox","visible":true,"position":"stackedTL"},{"element":"taskbar","visible":true,"position":"stackedTL"},{"element":"centerBox","visible":true,"position":"stackedBR"},{"element":"rightBox","visible":true,"position":"stackedBR"},{"element":"dateMenu","visible":true,"position":"stackedBR"},{"element":"systemMenu","visible":true,"position":"stackedBR"},{"element":"desktopButton","visible":false,"position":"stackedBR"}]}'';
        };
        "org/gnome/shell/extensions/wsmatrix" = {
          show-popup = false;
        };
        "org/gnome/shell/extensions/quake-terminal" = {
          # terminal-id = "org.gnome.Console.desktop";
          terminal-id = "kitty.desktop";
          terminal-shortcut = ["<Super>x"];
          animation-time = 0;
          vertical-size = 90;
          always-on-top = true;
          render-on-current-monitor = false;
          auto-hide-window = false;
          monitor-screen = 0;
        };
        "org/gnome/shell" = {
          disable-user-extensions = false;
          welcome-dialog-last-shown-version = "99.0";
          always-show-log-out = true;

          favorite-apps = [
            "firefox.desktop"
            "code.desktop"
            # "org.gnome.Terminal.desktop"
            # "virt-manager.desktop"
            # "org.gnome.Nautilus.desktop"
          ];

          # `gnome-extensions list` for a list
          enabled-extensions = [
            "dash-to-panel@jderose9.github.com"
            "weatheroclock@CleoMenezesJr.github.io"
            "system-monitor-next@paradoxxx.zero.gmail.com"
            "wsmatrix@martin.zurowietz.de"
            "workspace-indicator@gnome-shell-extensions.gcampax.github.com"
            "quake-terminal@diegodario88.github.io"
            "azwallpaper@azwallpaper.gitlab.com"
            "SmartAutoMoveNG@lauinger-clan.de"
            "no-overview@fthx"
            "live-lockscreen@nick-redwill"
          ];
        };
      };
    }) gnomeUsers;
  };
}
