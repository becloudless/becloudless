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

    system.activationScripts = lib.mapAttrs' (name: ucfg:
      lib.nameValuePair "cosmic-initial-setup-done-${name}" {
        text = ''
          install -d -m 755 /home/
          install -d -o ${name} -g users -m 700 /home/${name}
          install -d -o ${name} -g users -m 755 /home/${name}/.config
          install -o ${name} -g users -m 644 /dev/null /home/${name}/.config/cosmic-initial-setup-done
        '';
      }
    ) cosmicUsers;

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
