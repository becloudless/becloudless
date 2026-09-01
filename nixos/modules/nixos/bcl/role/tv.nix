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

    hardware.graphics = {
      enable = true;
    };


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

            # Wait for network before starting jellyfin.
            #
            # NOTE: this previously used `nm-online -q`, which waits for
            # NetworkManager's own global connectivity state to become
            # "connected". That silently hangs FOREVER (retried every 1s,
            # each nm-online call itself blocking up to its own ~30s
            # internal timeout) on hosts with
            # `bcl.role.tv.miracast.enable = true`: that role's
            # `networking.networkmanager.unmanaged = [ "type:wifi" ]`
            # hands the wifi interface entirely to miracast's own
            # wpa_supplicant/dhcpcd instead, so NetworkManager has no
            # managed device left at all and can never report
            # "connected" - confirmed live via the jellyfin startup log
            # sitting on the nm-online line indefinitely right after
            # enabling miracast. Checking for an actual default route
            # instead works regardless of which component (NetworkManager
            # or miracast/dhcpcd) brought the interface up.
            until ${pkgs.iproute2}/bin/ip route show default | ${pkgs.gnugrep}/bin/grep -q default; do sleep 1; done

            # Volume to 100%
            #
            # Waiting for `pactl info` to succeed is NOT enough: it only
            # confirms the pipewire-pulse server itself is up, not that the
            # actual HDMI sink node has been created yet (ALSA HDMI
            # codec/EDID detection can still be in progress) - confirmed live
            # on bureau-0, `pactl set-sink-volume @DEFAULT_SINK@ 100%` failed
            # with "Failed to get sink information: No such entity" right
            # after a successful `pactl info`, silently leaving the sink at
            # whatever volume it already had. Wait for a real default sink
            # name instead, and retry the volume set a few times in case of a
            # further race between the sink appearing and it being fully
            # usable.
            #
            # Run in a background subshell so a slow-to-appear sink doesn't
            # delay starting jellyfin-desktop itself.
            (
              until pactl info >/dev/null 2>&1; do sleep 0.5; done
              until [ -n "$(pactl get-default-sink 2>/dev/null)" ]; do sleep 0.5; done
              for i in $(seq 1 10); do
                pactl set-sink-volume @DEFAULT_SINK@ 100% && break
                sleep 0.5
              done
            ) &

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

            # Miracast video sink (miracle-gst's own `gst-launch-1.0 ...
            # autovideosink` pipeline, which auto-selects waylandsink on
            # Wayland): unlike jellyfin-desktop's windows above, this is a
            # single toplevel with no CEF UI layered on top of it, so
            # sway's normal single-fullscreen-per-workspace exclusivity is
            # not an issue here - use real compositor-driven fullscreen
            # instead of the floating+100ppt-resize trick. That trick alone
            # left the cast window small/native-resolution (1280x720)
            # instead of filling the screen; an earlier attempt to fix that
            # by setting waylandsink's OWN `fullscreen=true` element
            # property (rather than a sway rule) crashed the pipeline
            # outright (gst_wl_window_ensure_fullscreen: assertion 'self'
            # failed, since the property is applied before the sink's
            # Wayland window exists) - killing audio too, since video and
            # audio are two branches of the SAME single gst-launch-1.0
            # process. Sway's own `fullscreen enable` instead sends an
            # xdg_toplevel configure event carrying the real target
            # width/height - GstWlWindow's own configure handler
            # (handle_xdg_toplevel_configure in gst-plugins-bad's
            # gstwlwindow.c) DOES resize its render rectangle to match
            # whatever width/height the compositor requests, so this
            # should genuinely fill the screen without touching the
            # pipeline or its properties at all. gst-launch-1.0 sets its
            # own Wayland app_id via g_get_prgname(), i.e. its own argv[0]
            # basename - confirmed live via `swaymsg -t get_tree` showing
            # `"app_id": "gst-launch-1.0"` for the running cast window.
            for_window [app_id="gst-launch-1.0"] fullscreen enable

            exec "${jellyfinScript}; ${pkgs.sway}/bin/swaymsg exit"
          '';
          startScript = pkgs.writeShellScript "start-sway" ''
            ${lib.optionalString config.bcl.role.tv.forceSoftwareGL ''
              # On GPU-less hosts (e.g. CI VMs), wlroots refuses to start with
              # only a software rasterizer (llvmpipe) available unless
              # explicitly allowed.
              export WLR_RENDERER_ALLOW_SOFTWARE=1
            ''}
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
      bcl.jellium-desktop
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
