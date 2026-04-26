{ config, lib, inputs, ... }:

let
  nixosConfig = config;
  stUsers = lib.filterAttrs (_: u: u.enable) config.bcl.users.syncthing;
in
{
  options.bcl.users.syncthing = lib.mkOption {
    type = lib.types.attrsOf (lib.types.submodule {
      options = {
        enable = lib.mkEnableOption "Enable syncthing for this user";
        sopsFile = lib.mkOption {
          type = lib.types.nullOr lib.types.path;
          default = null;
          description = "Path to the sops secrets file containing the syncthing cert and key.";
        };
        remote = lib.mkOption {
          type = lib.types.submodule {
            options = {
              id = lib.mkOption { type = lib.types.str; default = ""; };
            };
          };
          default = {};
        };
        homeFolderId = lib.mkOption {
          type = lib.types.str;
          default = "";
        };
        folders = lib.mkOption {
          type = lib.types.attrsOf (lib.types.submodule {
            options = {
              id = lib.mkOption { type = lib.types.str; };
              key = lib.mkOption { type = lib.types.str; };
              endpoint = lib.mkOption { type = lib.types.str; };
            };
          });
          default = {};
        };
      };
    });
    default = {};
    description = "Syncthing per-user configuration, keyed by username.";
  };

  config = {
    assertions = lib.mapAttrsToList (name: ucfg: {
      assertion = ucfg.sopsFile != null;
      message = "bcl.users.syncthing.${name}.sopsFile must be set.";
    }) stUsers;

    sops.secrets = lib.mkMerge (lib.mapAttrsToList (name: ucfg: {
      "users.${name}.syncthing.cert" = {
        owner = name;
        sopsFile = ucfg.sopsFile;
        path = "/nix/home/${name}/.local/state/syncthing/cert.pem";
      };
      "users.${name}.syncthing.key" = {
        owner = name;
        sopsFile = ucfg.sopsFile;
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
            id = ucfg.remote.id;
            autoAcceptFolders = false;
          };
          folders =
            (lib.mapAttrs' (k: v: lib.nameValuePair k {
              id = v.id;
              path = "/nix/syncthing/home/${name}/${k}";
              devices = [ "${name}.syncthing.${nixosConfig.bcl.global.domain}" ];
            }) ucfg.folders)
            // lib.optionalAttrs (ucfg.homeFolderId != "") {
              "Home" = {
                id = ucfg.homeFolderId;
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
        "/nix/syncthing" = {
          hideMounts = true;
          users."${name}".directories = lib.attrNames ucfg.folders;
        };
      } // lib.optionalAttrs (ucfg.homeFolderId != "") {
        "/nix/syncthing/homes" = {
          hideMounts = true;
          users."${name}" = {
            directories = [
              # ".viminfo"
              ".tmux"
              # ".lesshst" # less replace the file
              ".docker"
              ".vscode-oss"
              ".config/chromium"
              ".config/Signal"
              ".local/bin"
              ".local/share/applications"
              ".local/share/desktop-directories"
              ".local/share/zoxide"
              ".config/menus"
              ".local/share/icons"
              ".config/gcloud"
              ".config/sops" # TODO replace by static
              ".config/VSCodium"
              ".config/keepassxc"
              ".wine"
              ".local/share/JetBrains/"
              ".config/JetBrains"
              ".java/.userPrefs/jetbrains"
            ];
            files = [
              ".z"
              ".local/share/gnome-shell/application_state"
            ];
          };
        };
      }
    ) stUsers);
  };
}
