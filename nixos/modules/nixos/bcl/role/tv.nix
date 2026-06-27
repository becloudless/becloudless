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
          modeSwitch = pkgs.writeText "mode-switch.lua" ''
            local original_mode = nil

            local function set_mode(fps, width, height)
              local mode = string.format("%dx%d@%.3fHz", width, height, fps)
              local result = mp.command_native({
                name = "subprocess",
                args = { "${pkgs.wlr-randr}/bin/wlr-randr", "--output", "HDMI-A-1", "--mode", mode },
                capture_stderr = true,
                capture_stdout = true,
              })
              if result.status ~= 0 then
                -- try without fractional fps (e.g. 24 instead of 23.976)
                mode = string.format("%dx%d@%dHz", width, height, math.floor(fps + 0.5))
                mp.command_native({
                  name = "subprocess",
                  args = { "${pkgs.wlr-randr}/bin/wlr-randr", "--output", "HDMI-A-1", "--mode", mode },
                  capture_stderr = true,
                })
              end
            end

            mp.register_event("file-loaded", function()
              local fps = mp.get_property_number("container-fps")
              local width = mp.get_property_number("width")
              local height = mp.get_property_number("height")
              if fps and width and height then
                if original_mode == nil then
                  local proc = mp.command_native({
                    name = "subprocess",
                    args = { "${pkgs.wlr-randr}/bin/wlr-randr" },
                    capture_stdout = true,
                  })
                  original_mode = (proc.stdout or ""):match("(%d+x%d+@%S+) px, current")
                end
                set_mode(fps, width, height)
              end
            end)

            mp.register_event("end-file", function()
              if original_mode then
                mp.command_native({
                  name = "subprocess",
                  args = { "${pkgs.wlr-randr}/bin/wlr-randr", "--output", "HDMI-A-1", "--mode", original_mode },
                  capture_stderr = true,
                })
                original_mode = nil
              end
            end)
          '';
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
            mkdir -p ~/.config/jellyfin-desktop ~/.config/mpv/scripts
            cp ${jellyfinSettings} ~/.config/jellyfin-desktop/settings.json
            cp ${modeSwitch} ~/.config/mpv/scripts/mode-switch.lua
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
