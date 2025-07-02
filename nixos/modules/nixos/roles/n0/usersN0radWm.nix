{ config, lib, pkgs, ... }: {

  config = lib.mkIf (config.bcl.role.name == "n0") {
    #  TODO: move all that somewher else

    systemd.tmpfiles.rules = [
      # those things stay on the device
      "d /nix/home/n0rad/.local 0700 n0rad users"
      "d /nix/home/n0rad/.local/share 0700 n0rad users"
      "d /nix/home/n0rad/.local/state 0700 n0rad users"
      "d /nix/home/n0rad/.local/state/wireplumber 0700 n0rad users"
      "d /nix/home/n0rad/.config 0700 n0rad users"
      "d /nix/home/n0rad/.config/VirtualBox 0700 n0rad users"
      "d /nix/home/n0rad/.cache 0700 n0rad users"
      "d /nix/home/n0rad/Tmp 0700 n0rad users"
    ];


    users.users.n0rad = {
      extraGroups = [ "networkmanager" "keyd" "audio" "scanner" ];
    };


    environment.persistence."/nix" = {
      hideMounts = true;
      users.n0rad = {
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
