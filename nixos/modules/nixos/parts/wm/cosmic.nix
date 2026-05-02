{ config, lib, pkgs, inputs, ... }:

let
  cosmicUsers = lib.filterAttrs (name: ucfg: ucfg.wm == "cosmic") config.bcl.users.users;
  unstable = inputs.nixpkgs-unstable.legacyPackages.${pkgs.system};
in
{
  config = lib.mkIf (cosmicUsers != {}) {
    services.displayManager.cosmic-greeter.enable = true;
    services.desktopManager.cosmic.enable = true;
    services.system76-scheduler.enable = true;
    services.flatpak.enable = true; # for cosmic-store


    # unstable
    services.displayManager.cosmic-greeter.package = with unstable; cosmic-greeter;
    environment.cosmic.excludePackages = with pkgs; [
      cosmic-applets
      cosmic-applibrary
      cosmic-bg
      cosmic-comp
      cosmic-files
      cosmic-idle
      cosmic-initial-setup
      cosmic-launcher
      cosmic-notifications
      cosmic-osd
      cosmic-panel
      cosmic-session
      cosmic-settings
      cosmic-settings-daemon
      cosmic-workspaces-epoch
      # not core
      cosmic-edit
      cosmic-icons
      cosmic-player
      cosmic-randr
      cosmic-screenshot
      cosmic-term
      cosmic-wallpapers
      pop-icon-theme
      pop-launcher
      cosmic-store
    ];
    environment.systemPackages = with unstable; [
      cosmic-applets
      cosmic-applibrary
      cosmic-bg
      cosmic-comp
      cosmic-files
      cosmic-idle
      cosmic-initial-setup
      cosmic-launcher
      cosmic-notifications
      cosmic-osd
      cosmic-panel
      cosmic-session
      cosmic-settings
      cosmic-settings-daemon
      cosmic-workspaces-epoch
      # not core
      cosmic-edit
      cosmic-icons
      cosmic-player
      cosmic-randr
      cosmic-screenshot
      cosmic-term
      cosmic-wallpapers
      pop-icon-theme
      pop-launcher
      cosmic-store
    ];




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
            users."${name}".directories = [
              ".local/share/flatpak"
              ".local/state/cosmic"
              ".local/state/cosmic-comp"  # monitor state
            ];
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
