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
    services.speechd.enable = lib.mkForce false; # remove mbrola-voices dependency that is huge
    security.sudo.wheelNeedsPassword = false;


    bcl.users.users.tv = {
      # wm.name = "dwm";
      # autoLogin = true;
    };

    programs.sway = {
      enable = true;
      wrapperFeatures.gtk = true;
    };

    services.greetd = {
      enable = true;
      settings.default_session = {
        command = "${pkgs.sway}/bin/sway --config ${pkgs.writeText "sway-jellyfin-kiosk.conf" ''
          output * bg #000000 solid_color
          default_border none
          seat * hide_cursor 3000
          for_window [app_id=\".*\"] fullscreen enable
          exec sh -c 'jellyfin-desktop; swaymsg exit'
        ''}";
        user = "tv";
      };
    };


    environment.systemPackages = with pkgs; [
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