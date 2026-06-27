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
            local sway_display_file = "/tmp/tv-sway-wayland-display"
            local wlr_randr_bin = "${pkgs.wlr-randr}/bin/wlr-randr"
            local original_mode = nil

            local function read_file(path)
              local f = io.open(path, "r")
              if not f then return nil end
              local s = f:read("*l")
              f:close()
              return s
            end

            local function wlr_randr(args)
              local wayland = read_file(sway_display_file)
              if not wayland then return end
              local cmd = { wlr_randr_bin }
              for _, v in ipairs(args) do cmd[#cmd+1] = v end
              mp.command_native({
                name = "subprocess",
                args = cmd,
                env = { "WAYLAND_DISPLAY=" .. wayland, "XDG_RUNTIME_DIR=" .. (os.getenv("XDG_RUNTIME_DIR") or "") },
                capture_stdout = true,
                capture_stderr = true,
              })
            end

            mp.register_event("file-loaded", function()
              local fps    = mp.get_property_number("container-fps")
              local width  = mp.get_property_number("width")
              local height = mp.get_property_number("height")
              if not (fps and width and height) then return end
              if not original_mode then
                local wayland = read_file(sway_display_file)
                if wayland then
                  local r = mp.command_native({
                    name = "subprocess",
                    args = { wlr_randr_bin },
                    env = { "WAYLAND_DISPLAY=" .. wayland, "XDG_RUNTIME_DIR=" .. (os.getenv("XDG_RUNTIME_DIR") or "") },
                    capture_stdout = true, capture_stderr = true,
                  })
                  original_mode = (r.stdout or ""):match("(%d+x%d+) px, (%S+) Hz %(preferred, current%)")
                  if original_mode then
                    -- combine into WxH@Hz format for restore
                    local w, hz = (r.stdout or ""):match("(%d+x%d+) px, (%S+) Hz %(preferred, current%)")
                    original_mode = w and (w .. "@" .. hz) or nil
                  end
                end
              end
              -- format: WxH@Hz (e.g. 3840x2160@23.976)
              local mode = string.format("%dx%d@%.3f", width, height, fps)
              wlr_randr({ "--output", "HDMI-A-1", "--mode", mode })
            end)

            mp.register_event("end-file", function()
              if original_mode then
                wlr_randr({ "--output", "HDMI-A-1", "--mode", original_mode })
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
            echo "$WAYLAND_DISPLAY" > /tmp/tv-sway-wayland-display
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
