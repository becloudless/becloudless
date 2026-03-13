{ config, lib, pkgs, inputs, ... }:

let
  cfg = config.bcl.users;

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

    sops.secrets = lib.mkMerge (lib.mapAttrsToList (name: ucfg:
      lib.optionalAttrs (ucfg.sopsFile != null) {
        "users.${name}.hashedPassword" = {
          neededForUsers = true;
          sopsFile = ucfg.sopsFile;
        };
      }
    ) cfg);

    home-manager.users = lib.mapAttrs (name: ucfg: { lib, pkgs, ... }: {
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

    environment.persistence."/nix" = {
      hideMounts = true;
      users = lib.mapAttrs (name: ucfg: {
        directories = [
          ".cache"
          "Tmp"
          ".local/share/docker"
          ".local/state/wireplumber"
          ".config/VirtualBox"
        ];
      }) cfg;
    };
  };
}
