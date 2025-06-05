{ config, lib, pkgs, inputs, ... }:

let
  cfg = config.bcl.user;
in
{
  options.bcl.user = {
    enable = lib.mkEnableOption "Enable";
    name = lib.mkOption { type = lib.types.str; };
  };

  config = lib.mkIf cfg.enable {
    users.users."${cfg.name}" = {
      isNormalUser = true;
      group = "users";
      hashedPasswordFile = config.sops.secrets."users.${cfg.name}.password".path;
    };

    home-manager.users."${cfg.name}" = { lib, pkgs, ... }: {
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
    };

    systemd.tmpfiles.rules = [
      "d /nix/home/${cfg.name}/.local 0700 ${cfg.name} users"
      "d /nix/home/${cfg.name}/.local/share 0700 ${cfg.name} users"
      "d /nix/home/${cfg.name}/.local/state 0700 ${cfg.name} users"
      "d /nix/home/${cfg.name}/.local/state/wireplumber 0700 ${cfg.name} users"
      "d /nix/home/${cfg.name}/.config 0700 ${cfg.name} users"
      "d /nix/home/${cfg.name}/.config/VirtualBox 0700 ${cfg.name} users"
      "d /nix/home/${cfg.name}/.cache 0700 ${cfg.name} users"
      "d /nix/home/${cfg.name}/Tmp 0700 ${cfg.name} users"
    ];

    environment.persistence."/nix" = {
      hideMounts = true;
      users."${cfg.name}" = {
        directories = [
          ".cache"
          "Tmp"
          ".local/share/docker" # for rootless docker
          ".local/state/wireplumber" # audio setup
          ".config/VirtualBox"
        ];
      };
    };

  };
}
