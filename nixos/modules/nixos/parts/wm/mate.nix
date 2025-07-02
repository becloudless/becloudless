{ config, lib, pkgs, ... }:
{
  config = lib.mkIf (config.bcl.wm.name == "mate") {
    services.xserver.desktopManager.mate.enable = true;

    home-manager.users."${config.bcl.wm.user}" = { lib, pkgs, ... }: {
      dconf.settings = with lib.hm.gvariant; {
        "org/mate/panel/toplevels/top" = {
          size = 18;
        };

        "org/mate/panel/general" = {
          toplevel-id-list = [ "top" ];
          object-id-list = [
            "notification-area"
            "object-0"
            "object-1"
            "object-2"
            "object-3"
          ];
        };

        "org/mate/panel/objects/object-0" = {
          object-type = "menu";
          panel-right-stick = false;
          position = 0;
          toplevel-id = "top";
          use-menu-path = false;
          tooltip = "Menu compact";
        };

        "org/mate/panel/objects/object-1" = {
          object-type = "applet";
          panel-right-stick = false;
          position = 18;
          toplevel-id = "top";
          applet-iid = "WnckletFactory::WindowListApplet";
        };

        "org/mate/panel/objects/object-2" = {
          object-type = "applet";
          panel-right-stick = true;
          toplevel-id = "top";
          applet-iid = "ClockAppletFactory::ClockApplet";
        };

        "org/mate/panel/objects/object-2/perfs" = {
            cities =  [
              ''<location name="" city="Paris" timezone="Europe/Paris" latitude="48.733334" longitude="2.400000" code="LFPO" current="false"/>''
            ];
        };

        "org/mate/panel/objects/object-3" = {
          object-type = "applet";
          panel-right-stick = false;
          position = 1260;
          toplevel-id = "top";
          applet-iid = "MultiLoadAppletFactory::MultiLoadApplet";
        };

        "org/mate/panel/objects/object-3/perfs" = {
            view-memload = true;
            view-netload = true;
            view-loadavg = true;
            view-diskload = true;
#            speed = mkUint32 2000;
#            size = mkUint32 50;
        };


#        "ca/desrt/dconf-editor" = {
#          relocatable-schemas-user-paths = {
#            "ca.desrt.dconf-editor.Demo.Relocatable" = "/ca/desrt/dconf-editor/Demo/relocatable/";
#            "org.mate.panel.applet.window-list-previews" = "/org/mate/panel/objects/object-1/prefs/";
#            "org.mate.panel.applet.clock" = "/org/mate/panel/objects/object-2/prefs/";
#            "org.mate.panel.applet.multiload" = "/org/mate/panel/objects/object-3/prefs/";
#          };
#        };

        #######################

        "org/gtk/settings/file-chooser" = {
          sort-directories-first = true;
        };

        "org/mate/desktop/interface" = {
          gtk-theme = "Adwaita-dark";
        };

        "org/mate/desktop/background" = {
          picture-filename = "/home/kwiskas/Pictures/chaussette.jpg";
        };

      };
    };
  };
}
