{ config, lib, pkgs, ... }:

let
  cosmicUsers = lib.filterAttrs (name: ucfg: ucfg.wm == "cosmic") config.bcl.users;
in
{
  config = lib.mkIf (cosmicUsers != {}) {
    services.displayManager.cosmic-greeter.enable = true;
    services.desktopManager.cosmic.enable = true;
    services.system76-scheduler.enable = true;
#    services.xserver.xkb.layout = "fr";

    programs.firefox.preferences = {
        # disable libadwaita theming for Firefox
        "widget.gtk.libadwaita-colors.enabled" = false;
      };

    environment.persistence = lib.mkMerge (
      lib.mapAttrsToList (name: ucfg:
        lib.optionalAttrs (ucfg.syncthing.homeFolderId != "") {
          "/nix/syncthing/homes" = {
            hideMounts = true;
            users."${name}".directories = [ ".config/cosmic" ];
          };
        }
      ) cosmicUsers
    );
  };
}
