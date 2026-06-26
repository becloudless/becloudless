{ inputs, config, lib, pkgs, ... }:
{

  imports = [
    "${inputs.nix-flatpak}/modules/nixos.nix"
  ];

  options.bcl.role.tv = {
    audioType = lib.mkOption {
         type = lib.types.str;
         default = "basic";
      };
    audioDevice = lib.mkOption {
         type = lib.types.str;
         default = "auto";
      };
    jellyfinUrl = lib.mkOption {
         type = lib.types.str;
         default = "https://jellyfin.${config.bcl.global.domain}";
      };
  };

  config = lib.mkMerge [
    { bcl.role.knownRoles = [ "tv" ]; }
    (lib.mkIf (config.bcl.role.name == "tv") {
    bcl.boot.quiet = true;
    bcl.sound.enable = true;
    bcl.wifi.enable = true;
    services.speechd.enable = lib.mkforce false; # remove mbrola-voices dependency that is huge
    security.sudo.wheelNeedsPassword = false;


    bcl.users.users.tv = {
      wm.name = "gnome";
      autoLogin = true;
    };

    home-manager.users.tv = { lib, pkgs, ... }: {
      home = {
        stateVersion = "23.11"; # never touch that
      };

      imports = [ (inputs.impermanence + "/home-manager.nix") ];

      home.file.".xprofile".text = ''
        if [ -z $_XPROFILE_SOURCED ]; then
          export _XPROFILE_SOURCED=1

          xsetroot -solid black # black background
          xset -dpms      # disable xorg screen going to sleep
          xset s off      # disable xorg screensaver
          # xdotool mousemove 100 100 && xdotool click 1

          # TODO this is a hack
          pactl set-sink-volume @DEFAULT_SINK@ 100%
          pactl set-sink-volume alsa_output.pci-0000_00_0e.0.hdmi-stereo 100% # TODO

          # TODO wait for network
          # while ! ping -c 1 -W 1 192.168.40.12; do sleep 1; done;
          bash -c "while true; do jellyfin-desktop; sleep 5; done" &
          bash -c "sleep 20; xdotool mousemove 100 100; xdotool click 1; amixer set Master 95%;" &
        fi
      '';
    };


    # services.greetd = {
    #   enable = true;
    #   settings.default_session = {
    #     command = "${pkgs.cage}/bin/cage -s -- ${pkgs.bcl.jellyfin-desktop}/bin/jellyfin-desktop";
    #     user = "tv";
    #   };
    # };


    environment.systemPackages = with pkgs; [
      cage
      pulseaudio
      bcl.jellyfin-desktop
    ];

    systemd.tmpfiles.rules = [
      "d /nix/home/tv 0700 tv users"
    ];

    environment.persistence."/nix" = {
      users."tv".directories = [
        ".config/jellyfin-desktop"
      ];
    };

  })
  ];
}