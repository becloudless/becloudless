{ config, lib, pkgs, ... }:

let
  cosmicUsers = lib.filterAttrs (name: ucfg: ucfg.wm == "cosmic") config.bcl.users.users;
in
{
  config = lib.mkIf (cosmicUsers != {}) {
    services.displayManager.cosmic-greeter.enable = true;
    services.desktopManager.cosmic.enable = true;
    services.system76-scheduler.enable = true;
    config.services.flatpak.enable = true;

    programs.firefox.preferences = {
        # disable libadwaita theming for Firefox
        "widget.gtk.libadwaita-colors.enabled" = false;
      };

    # TODO this activates for all users, not only those on cosmic
    system.userActivationScripts.cosmic-initial-setup-done = ''
      install -d -m 755 "$HOME/.config"
      install -m 644 /dev/null "$HOME/.config/cosmic-initial-setup-done"
    '';

    environment.persistence = lib.mkMerge (
      lib.mapAttrsToList (name: ucfg:
        {
          "/nix" = {
            hideMounts = true;
            users."${name}".directories = [ ".local/state/cosmic" ];

          };
          "/nix/syncthing/homes" = {
            hideMounts = true;
            users."${name}".directories = [ ".config/cosmic" ];
          };
        }
      ) cosmicUsers
    );
  };
}
