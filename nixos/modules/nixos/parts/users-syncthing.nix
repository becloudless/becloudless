{ config, lib, inputs, ... }:

let
  cfg = config.bcl.users.users;
  nixosConfig = config;
  stUsers = lib.filterAttrs (_: u: u.syncthing.enable) cfg;
in
{
  options.bcl.users.syncthing.sopsFile = lib.mkOption {
    type = lib.types.nullOr lib.types.path;
    default = null;
    description = "Default sops file for syncthing cert/key, applied to all users unless overridden.";
  };

  config = {
    assertions = lib.mapAttrsToList (name: ucfg: {
      assertion = ucfg.syncthing.sopsFile != null;
      message = "bcl.users.${name}.syncthing.sopsFile must be set when syncthing is enabled.";
    }) stUsers;

    sops.secrets = lib.mkMerge (lib.mapAttrsToList (name: ucfg: {
      "users.${name}.syncthing.cert" = {
        owner = name;
        sopsFile = ucfg.syncthing.sopsFile;
        path = "/nix/home/${name}/.local/state/syncthing/cert.pem";
      };
      "users.${name}.syncthing.key" = {
        owner = name;
        sopsFile = ucfg.syncthing.sopsFile;
        path = "/nix/home/${name}/.local/state/syncthing/key.pem";
      };
    }) stUsers);

    home-manager.users = lib.mapAttrs (name: ucfg: { lib, ... }: {
      services.syncthing = {
        enable = true;
        settings = {
          options = {
            localAnnounceEnabled = false;
            relaysEnabled = true;
            urAccepted = -1;
            listenAddresses = [ "relay://syncthing.${nixosConfig.bcl.global.domain}:22067/?id=${nixosConfig.bcl.global.syncthing.relayId}" ];
          };
          devices."${name}.syncthing.${nixosConfig.bcl.global.domain}" = {
            id = ucfg.syncthing.remote.id;
            autoAcceptFolders = false;
          };
          folders =
            (lib.mapAttrs' (k: v: lib.nameValuePair k {
              id = v.id;
              path = "/nix/syncthing/home/${name}/${k}";
              devices = [ "${name}.syncthing.${nixosConfig.bcl.global.domain}" ];
            }) ucfg.syncthing.folders)
            // lib.optionalAttrs (ucfg.syncthing.homeFolderId != "") {
              "Home" = {
                id = ucfg.syncthing.homeFolderId;
                path = "/nix/syncthing/homes/home/${name}";
                devices = [ "${name}.syncthing.${nixosConfig.bcl.global.domain}" ];
                fsWatcherEnabled = false;
                rescanIntervalS = 3600;
              };
            };
        };
      };
    }) stUsers;

    # TODO this is gnome specific
    system.activationScripts = lib.mkMerge (lib.mapAttrsToList (name: ucfg: {
      "accountsservice-icon-${name}" = {
        text = ''
          mkdir -p /var/lib/AccountsService/{icons,users}
          echo -e "[User]\nSession=gnome\nIcon=/var/lib/AccountsService/icons/${name}\n" > /var/lib/AccountsService/users/${name}
          cp /nix/syncthing/home/${name}/Pictures/face.png /var/lib/AccountsService/icons/${name} || true
        '';
      };
    }) stUsers);

    environment.persistence = lib.mkMerge (lib.mapAttrsToList (name: ucfg:
      {
        # keep on syncthing folders
        "/nix/syncthing" = {
          hideMounts = true;
          users."${name}".directories = lib.attrNames ucfg.syncthing.folders;
        };
      } // lib.optionalAttrs (ucfg.syncthing.homeFolderId != "") {
        # keep from home folder on syncthing 'Home' folder
        "/nix/syncthing/homes" = {
          hideMounts = true;
          users."${name}" = {
            directories = [
              # ".viminfo"
              ".tmux"
              # ".lesshst" # less replace the file
              ".docker" # must be the directory so it can mounted by bbc commands
              ".vscode-oss"
              ".config/chromium"
              ".config/Signal"
              ".local/bin" # scripts and bbc
              ".local/share/applications" # to keep plex chromium application
              ".local/share/desktop-directories"
              ".local/share/zoxide"
              ".config/menus" # .desktop applications into menu
              ".local/share/icons" # .desktop icons
              ".config/gcloud"
              ".config/sops" # TODO replace by static
              ".config/VSCodium"
              ".config/keepassxc"
              ".wine"
              ".local/share/JetBrains/" # plugins and license
              ".config/JetBrains" # looks required for license
              ".java/.userPrefs/jetbrains"
            ];
            files = [
              ".z"
              ".local/share/gnome-shell/application_state" # trusted .desktop applications
            ];
          };
        };
      }
    ) stUsers);
  };
}

