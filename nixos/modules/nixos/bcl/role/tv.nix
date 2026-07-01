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

            # Wait for the TV to be ready (xrandr shows a connected output)
            until ${pkgs.xorg.xrandr}/bin/xrandr --query 2>/dev/null | grep -q ' connected'; do
              sleep 1
            done
            randr_out=$(${pkgs.xorg.xrandr}/bin/xrandr --query 2>/dev/null) || true
            output=$(echo "$randr_out" | grep -m1 ' connected' | awk '{print $1}')
            resolution=$(echo "$randr_out" | grep -m1 '\*' | awk '{print $1}')
            width=$(echo "$resolution" | cut -dx -f1)
            height=$(echo "$resolution" | cut -dx -f2)

            # Only switch to 23.976 if both the output and mode are actually available (TODO: https://github.com/jellyfin/jellyfin-desktop/issues/247)
            mode_rate=$(echo "$randr_out" | awk -v res="$resolution" '$1==res {for(i=2;i<=NF;i++) if ($i ~ /^23\.9/) print $i}' | head -1 | tr -d '*+')
            if [ -n "$output" ] && [ -n "$resolution" ] && [ -n "$mode_rate" ]; then
              # Wait a bit, changing resolution on slow TV start, makes it ignoring the command
              sleep 5
              ${pkgs.xorg.xrandr}/bin/xrandr --output "$output" --mode "$resolution" --rate "$mode_rate" || true
            fi

            # Volume to 100%
            until pactl info >/dev/null 2>&1; do sleep 0.5; done
            pactl set-sink-volume @DEFAULT_SINK@ 100%

            # Wait for network before starting jellyfin
            until ${pkgs.networkmanager}/bin/nm-online -q 2>/dev/null; do sleep 1; done

            cat > ~/.config/jellyfin-desktop/settings.json <<EOF
            # {"serverUrl":"${config.bcl.role.tv.jellyfinUrl}","windowDecorations":"server","windowWidth":''${width:-1920},"windowHeight":''${height:-1080},"windowLogicalWidth":''${width:-1920},"windowLogicalHeight":''${height:-1080}}
            {"serverUrl":"${config.bcl.role.tv.jellyfinUrl}","windowDecorations":"server"}
            EOF
            export JELLYFIN_DESKTOP_LOG_LEVEL=debug
            export JELLYFIN_DESKTOP_LOG_FILE=~/.config/jellyfin-desktop/jellyfin-desktop.log

            # Start screensaver just before jellyfin to be hover jellyfin window
            # screensaver takes time to start and will arrive after jellyfin
            systemctl --user start screensaver.service || true

            jellyfin-desktop ${lib.optionalString config.bcl.role.tv.disableGpuCompositing "--disable-gpu-compositing"}
          '';
          xinitScript = pkgs.writeShellScript "start-x-session" ''
            ${pkgs.openbox}/bin/openbox &
            ${pkgs.unclutter}/bin/unclutter --timeout 100 --jitter 2 --ignore-scrolling &
            exec ${jellyfinScript}
          '';
          startScript = "${pkgs.xorg.xinit}/bin/xinit ${xinitScript} -- ${pkgs.xorg.xorgserver}/bin/X :0 vt1 -keeptty -nolisten tcp";
        in "${startScript}";
        user = "tv";
      };
    };

    home-manager.users.tv = { lib, pkgs, ... }: {
      home.file.".config/openbox/rc.xml".text = ''
        <?xml version="1.0"?>
        <openbox_config xmlns="http://openbox.org/3.4/rc">
          <applications>
            <application name="*" class="*">
              <decor>no</decor>
              <fullscreen>yes</fullscreen>
              <focus>yes</focus>
            </application>
          </applications>
        </openbox_config>
      '';
    };

    environment.systemPackages = with pkgs; [
      pulseaudio
      xorg.xrandr
      xorg.xorgserver
      xorg.xinit
      openbox
      unclutter
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
