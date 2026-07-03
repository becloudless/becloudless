{ config, lib, pkgs, ... }:
{
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
    disableGpuCompositing = lib.mkOption {
      type = lib.types.bool;
      default = false;
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

    bcl.users.users.tv = {};

    services.greetd = {
      enable = true;
      settings.default_session = {
        command = let
          jellyfinScript = pkgs.writeShellScript "start-jellyfin" ''
            exec > ~/.config/jellyfin-desktop/start-jellyfin.log 2>&1
            set -x

            # lock contain machine name, cleanup any previous lock files to support renamed system 
            rm -f ~/.cache/jellyfin-desktop/SingletonLock ~/.cache/jellyfin-desktop/SingletonCookie

            # Wait for the TV to be ready (wlr-randr shows an active resolution)
            until ${pkgs.wlr-randr}/bin/wlr-randr 2>/dev/null | grep -q 'current'; do
              sleep 1
            done
            randr_out=$(${pkgs.wlr-randr}/bin/wlr-randr 2>/dev/null) || true
            output=$(echo "$randr_out" | grep -m1 '^[A-Za-z]' | awk '{print $1}')
            resolution=$(echo "$randr_out" | grep -m1 'current' | awk '{print $1}')
            width=$(echo "$resolution" | cut -dx -f1)
            height=$(echo "$resolution" | cut -dx -f2)


            # Only switch to 23.976 if both the output and mode are actually available (TODO: https://github.com/jellyfin/jellyfin-desktop/issues/247)
            if [ -n "$output" ] && [ -n "$resolution" ] && echo "$randr_out" | grep -q "$resolution.*23\.97"; then
              # Wait a bit, changing resolution on slow TV start, makes it ignoring the command
              sleep 5
              ${pkgs.wlr-randr}/bin/wlr-randr --output "$output" --mode "$resolution"@23.976 || true
            fi

            # Volume to 100%
            until pactl info >/dev/null 2>&1; do sleep 0.5; done
            pactl set-sink-volume @DEFAULT_SINK@ 100%

            # Wait for network before starting jellyfin
            until ${pkgs.networkmanager}/bin/nm-online -q 2>/dev/null; do sleep 1; done

            cat > ~/.config/jellyfin-desktop/settings.json <<EOF
            {"serverUrl":"${config.bcl.role.tv.jellyfinUrl}","windowDecorations":"server","windowWidth":''${width:-1920},"windowHeight":''${height:-1080},"windowLogicalWidth":''${width:-1920},"windowLogicalHeight":''${height:-1080}}
            EOF
            export JELLYFIN_DESKTOP_LOG_LEVEL=debug
            export JELLYFIN_DESKTOP_LOG_FILE=~/.config/jellyfin-desktop/jellyfin-desktop.log

            # Start screensaver just before jellyfin to be hover jellyfin window
            # screensaver takes time to start and will arrive after jellyfin
            systemctl --user start screensaver.service || true

            jellyfin-desktop ${lib.optionalString config.bcl.role.tv.disableGpuCompositing "--disable-gpu-compositing"}
          '';
          startScript = "${pkgs.labwc}/bin/labwc -s ${jellyfinScript}";
        in "${startScript}";
        user = "tv";
      };
    };

    home-manager.users.tv = { lib, pkgs, ... }: {
      home.file.".config/labwc/rc.xml".text = ''
        <?xml version="1.0"?>
        <labwc_config>
          <core>
            <decoration>none</decoration>
          </core>
          <mouse>
            <cursorHideTimeout>1</cursorHideTimeout>
          </mouse>
          <windowRules>
            <windowRule title="*">
              <action name="ToggleFullscreen"/>
            </windowRule>
          </windowRules>
        </labwc_config>
      '';

      # Pin mpv to the native Wayland GL context (labwc is always Wayland).
      # Without this, mpv's gpu-next "auto" probing falls through
      # waylandvk -> x11vk -> wayland -> x11egl whenever it suspects a
      # software renderer (e.g. llvmpipe in a GPU-less VM), and the last
      # hop crashes with `vo_x11_init: Assertion !vo->x11 failed`.
      # jellyfin-desktop uses its own mpv home (config_dir/mpv), not
      # ~/.config/mpv.
      home.file.".config/jellyfin-desktop/mpv/mpv.conf".text = ''
        gpu-context=wayland
      '';
    };

    environment.systemPackages = with pkgs; [
      pulseaudio
      wlr-randr
      labwc
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
