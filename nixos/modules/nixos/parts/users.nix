{ config, lib, pkgs, inputs, ... }:

let
  cfg = config.bcl.users;
  stUsers = lib.filterAttrs (_: u: u.syncthing.enable) cfg;
  nixosConfig = config;

  userOpts = { name, config, ... }: {
    options = {
      sopsFile = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        description = "Path to the sops secrets file containing the hashed password at key 'users.<name>.hashedPassword'.";
      };
      wm = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "Window manager / desktop environment to configure for this user (e.g. \"gnome\").";
      };
      autoLogin = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Whether to automatically log in as this user.";
      };
      syncthing = {
        enable = lib.mkEnableOption "Enable syncthing for this user";
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
    };
  };

in
{
  options.bcl.users = lib.mkOption {
    type = lib.types.attrsOf (lib.types.submodule userOpts);
    default = {};
    description = "Attribute set of users to create, keyed by username.";
  };

  config =
    let
      autoLoginUsers = lib.filterAttrs (name: ucfg: ucfg.autoLogin) cfg;
      autoLoginUser = if autoLoginUsers != {} then lib.head (lib.attrNames autoLoginUsers) else null;
    in
    {
      services.displayManager.autoLogin = lib.mkIf (autoLoginUser != null) {
        enable = true;
        user = autoLoginUser;
      };

      users.users = lib.mapAttrs (name: ucfg:
        {
          isNormalUser = true;
          group = "users";
        } // lib.optionalAttrs (ucfg.sopsFile != null) {
          hashedPasswordFile = config.sops.secrets."users.${name}.hashedPassword".path;
        }
      ) cfg;

      sops.secrets = lib.mkMerge (
        # user passwords
        (lib.mapAttrsToList (name: ucfg:
          lib.optionalAttrs (ucfg.sopsFile != null) {
            "users.${name}.hashedPassword" = {
              neededForUsers = true;
              sopsFile = ucfg.sopsFile;
            };
          }
        ) cfg)
        ++
        # syncthing certs
        (lib.mapAttrsToList (name: ucfg: {
          "users.${name}.syncthing.cert" = {
            owner = name;
            sopsFile = ucfg.sopsFile;
            path = "/nix/syncthing/${name}/config/cert.pem";
          };
          "users.${name}.syncthing.key" = {
            owner = name;
            sopsFile = ucfg.sopsFile;
            path = "/nix/syncthing/${name}/config/key.pem";
          };
        }) stUsers)
      );

      home-manager.users = lib.mapAttrs (name: ucfg: { lib, pkgs, config, ... }: {
        imports = [ (inputs.impermanence + "/home-manager.nix") ];

        home.file.".config/user-dirs.dirs".text = ''
          XDG_DESKTOP_DIR="$HOME/"
          XDG_DOWNLOAD_DIR="$HOME/Downloads"
          XDG_TEMPLATES_DIR="$HOME/"
          XDG_PUBLICSHARE_DIR="$HOME/"
          XDG_DOCUMENTS_DIR="$HOME/Documents"
          XDG_MUSIC_DIR="$HOME/Music"
          XDG_PICTURES_DIR="$HOME/Pictures"
          XDG_VIDEOS_DIR="$HOME/Videos"
        '';

        home.stateVersion = "23.11"; # never touch that

        services.syncthing = lib.mkIf ucfg.syncthing.enable {
          enable = true;
          cert = "/nix/syncthing/${name}/config/cert.pem";
          key = "/nix/syncthing/${name}/config/key.pem";
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
                path = "/nix/syncthing/${name}/${k}";
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
      }) cfg;

      systemd.tmpfiles.rules = lib.concatLists (lib.mapAttrsToList (name: ucfg: [
        "d /nix/home/${name}/.local 0700 ${name} users"
        "d /nix/home/${name}/.local/share 0700 ${name} users"
        "d /nix/home/${name}/.local/state 0700 ${name} users"
        "d /nix/home/${name}/.local/state/wireplumber 0700 ${name} users"
        "d /nix/home/${name}/.config 0700 ${name} users"
        "d /nix/home/${name}/.config/VirtualBox 0700 ${name} users"
        "d /nix/home/${name}/.cache 0700 ${name} users"
        "d /nix/home/${name}/Tmp 0700 ${name} users"
      ]) cfg);

      environment.persistence = lib.mkMerge (
        [
          {
            "/nix" = {
              hideMounts = true;
              users = lib.mapAttrs (_: _: {
                directories = [
                  ".cache"
                  "Tmp"
                  ".local/share/docker"
                  ".local/state/wireplumber"
                  ".config/VirtualBox"
                ];
              }) cfg;
            };
          }
        ]
        ++
        lib.mapAttrsToList (name: ucfg:
          {
            "/nix/syncthing" = {
              hideMounts = true;
              users."${name}".directories = lib.attrNames ucfg.syncthing.folders;
            };
          } // lib.optionalAttrs (ucfg.syncthing.homeFolderId != "") {
            "/nix/syncthing/homes" = {
              hideMounts = true;
              users."${name}" = {
                directories = [ ".mozilla" ];
                files = [ ".z" ];
              };
            };
          }
        ) stUsers
      );
    };
}
