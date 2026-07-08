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
      description = "required on old GPU not supported anymore by chromium";
    };
    forceSoftwareGL = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Required on GPU-less hosts like CI.";
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

            # Wait for network before starting jellyfin
            until ${pkgs.networkmanager}/bin/nm-online -q 2>/dev/null; do sleep 1; done

            # Volume to 100%
            until pactl info >/dev/null 2>&1; do sleep 0.5; done
            pactl set-sink-volume @DEFAULT_SINK@ 100%

            cat > ~/.config/jellyfin-desktop/settings.json <<EOF
            {"serverUrl":"${config.bcl.role.tv.jellyfinUrl}","windowDecorations":"csd", "windowMaximized": true}
            EOF
            export JELLYFIN_DESKTOP_LOG_LEVEL=debug
            export JELLYFIN_DESKTOP_LOG_FILE=~/.config/jellyfin-desktop/jellyfin-desktop.log

            # Start screensaver just before jellyfin to be hover jellyfin window
            # screensaver takes time to start and will arrive after jellyfin
            systemctl --user start screensaver.service || true

            ${lib.optionalString config.bcl.role.tv.forceSoftwareGL ''
              # On GPU-less hosts (e.g. CI VMs), Mesa's automatic driver
              # selection routes CEF's EGL context through zink (Vulkan
              # software rasterizer), which fails to pick a device
              # ("ZINK: failed to choose pdev") and segfaults CEF's GPU
              # process. Force the classic llvmpipe softpipe path instead.
              #
              # required for CI
              export LIBGL_ALWAYS_SOFTWARE=1
            ''}
            jellyfin-desktop ${lib.optionalString config.bcl.role.tv.disableGpuCompositing "--disable-gpu-compositing"}
          '';
          swayConfig = pkgs.writeText "tv-sway-config" ''
            default_border none
            default_floating_border none
            seat seat0 hide_cursor 1000
            # jellyfin-desktop renders video via an embedded libmpv Wayland
            # window layered under a transparent CEF UI window: two separate
            # xdg_shell toplevels, neither of which ever sets a window
            # title/app_id, matched here via the "shell" criterion instead
            # (always set). They're meant to be stacked on top of each
            # other (CEF's transparent regions reveal the mpv video
            # underneath), not tiled side by side or take turns being
            # fullscreen: sway (like i3) only allows one fullscreen window
            # per workspace, so "fullscreen enable" on both just makes them
            # fight over exclusivity and fall back to a 50/50 tiled split.
            # Instead float both and resize/position them to cover the
            # whole output, so they overlap and stack normally.
            for_window [shell="xdg_shell"] floating enable, resize set width 100 ppt height 100 ppt, move position 0 0
            exec "${jellyfinScript}; ${pkgs.sway}/bin/swaymsg exit"
          '';
          # sway itself has no windows to composite that need GPU-accelerated
          # rendering (it just floats/positions jellyfin-desktop's two
          # toplevels), so force wlroots' software (pixman) renderer for the
          # compositor rather than the default GLES2/Vulkan one. This leaves
          # the GPU fully available for jellyfin-desktop's own mpv/CEF
          # hardware decode+render (gpu-context=wayland).
          startScript = pkgs.writeShellScript "start-sway-tv" ''
            export WLR_RENDERER=pixman
            exec ${pkgs.sway}/bin/sway -c ${swayConfig}
          '';
        in "${startScript}";
        user = "tv";
      };
    };

    home-manager.users.tv = { lib, pkgs, ... }: {
      # Pin mpv to the native Wayland GL context (sway is always Wayland).
      # Without this, mpv's gpu-next "auto" probing falls through
      # waylandvk -> x11vk -> wayland -> x11egl whenever it suspects a
      # software renderer (e.g. llvmpipe in a GPU-less VM), and the last
      # hop crashes with `vo_x11_init: Assertion !vo->x11 failed`.
      # without it, IT tests in kvm fail.
      home.file.".config/jellyfin-desktop/mpv/mpv.conf".text = ''
        gpu-context=wayland
      '';
    };

    environment.systemPackages = with pkgs; [
      pulseaudio
      wlr-randr
      sway
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
