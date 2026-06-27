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

    systemd.services.greetd = {
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
    };

    services.greetd = {
      enable = true;
      settings.default_session = {
        command = let
          jellyfinSettings = pkgs.writeText "jellyfin-desktop-settings.json" (builtins.toJSON {
            serverUrl = config.bcl.role.tv.jellyfinUrl;
            windowMaximized = true;
            windowScale = 1.0;
            windowWidth = 3840;
            windowHeight = 2160;
            windowLogicalWidth = 3840;
            windowLogicalHeight = 2160;
            windowDecorations = "server";
          });
          startScript = pkgs.writeShellScript "start-jellyfin" ''
            mkdir -p ~/.config/jellyfin-desktop
            cp ${jellyfinSettings} ~/.config/jellyfin-desktop/settings.json
            output=$(${pkgs.wlr-randr}/bin/wlr-randr | grep -m1 '^[A-Za-z]' | awk '{print $1}')
            ${pkgs.wlr-randr}/bin/wlr-randr --output "$output" --mode 3840x2160@23.976  # TODO workaround waiting for https://github.com/jellyfin/jellyfin-desktop/issues/247
            jellyfin-desktop
            swaymsg exit
          '';
        in "${pkgs.sway}/bin/sway --config ${pkgs.writeText "sway-jellyfin-kiosk.conf" ''
          output * bg #000000 solid_color
          default_border none
          default_floating_border none
          seat * hide_cursor 3000
          exec ${startScript}
        ''}";
        user = "tv";
      };
    };


    environment.systemPackages = with pkgs; [
      pulseaudio
      wlr-randr
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
