{ inputs, config, lib, pkgs, ... }:
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
  };

  config = lib.mkMerge [
    { bcl.role.knownRoles = [ "tv" ]; }
    (lib.mkIf (config.bcl.role.name == "tv") {
    bcl.boot.quiet = true;
    bcl.sound.enable = true;
    bcl.wifi.enable = true;

    bcl.users.users.tv = {
      wm.name = "";
      autoLogin = false;
    };

    users.users.tv.extraGroups = [ "video" "render" "audio" ];

    services.speechd.enable = false; # remove mbrola-voices dependency that is huge

    security.sudo.wheelNeedsPassword = false;

    # cage: minimal Wayland kiosk compositor - runs jellyfin-desktop fullscreen.
    services.greetd = {
      enable = true;
      settings.default_session = {
        # QT_QPA_PLATFORM=xcb: force Qt to use X11 via cage's built-in Xwayland.
        # Native Wayland QPA causes black video (NativeSkiaOutputDevice failure in cage).
        # vblank_mode=3: force Mesa GLX vsync for mpv (GL_*_swap_control missing on Xwayland).
        # QTWEBENGINE_CHROMIUM_FLAGS: VA-API GPU decode in Chromium for HLS/htmlvideoplayer.
        # command = "${pkgs.cage}/bin/cage -s -- env QT_QPA_PLATFORM=xcb vblank_mode=3 QTWEBENGINE_CHROMIUM_FLAGS='--use-gl=desktop --enable-features=VaapiVideoDecoder,VaapiVideoDecodeLinuxGL' jellyfin-desktop";
        user = "tv";
      };
    };

    environment.systemPackages = with pkgs; [
      jellyfin-media-player
      cage
      pulseaudio
    ];

    systemd.tmpfiles.rules = [
      "d /nix/home/tv 0700 tv users"
    ];

    home-manager.users.tv = { lib, pkgs, ... }: {
      home = {
        stateVersion = "23.11"; # never touch that
      };

      imports = [ (inputs.impermanence + "/home-manager.nix") ];

      # Wayland environment for cage: EGL is native, VA-API works for libmpv.
      # QTWEBENGINE_CHROMIUM_FLAGS: VA-API decode in Chromium for HLS content.
      # home.file.".config/environment.d/jellyfin.conf".text = ''
      #   QTWEBENGINE_CHROMIUM_FLAGS=--enable-features=VaapiVideoDecoder,VaapiVideoDecodeLinuxGL
      # '';

      # Force WirePlumber to use the HDMI sink as the default audio output
      xdg.configFile."wireplumber/wireplumber.conf.d/50-hdmi-default.conf".text = ''
        wireplumber.settings = {
          default.audio.sink = "alsa_output.pci-0000_00_0e.0.hdmi-stereo"
        }
      '';

      home.file.".local/share/jellyfin-desktop/profiles.json".text = ''
        {
            "defaultProfile": "b6a136dc17a44b32a63eed3507a6f2d0"
        }
      '';

      home.file.".local/share/jellyfin-desktop/profiles/b6a136dc17a44b32a63eed3507a6f2d0/jellyfin-desktop.conf".text = ''
        {
            "sections": {
                "appleremote": {
                    "emulatepht": true
                },
                "audio": {
                    "channels": "2.0",
                    "device": "${config.bcl.role.tv.audioDevice}",
                    "devicetype": "${config.bcl.role.tv.audioType}",
                    "exclusive": false,
                    "normalize": false,
                    "passthrough.ac3": false,
                    "passthrough.dts": false,
                    "passthrough.dts-hd": false,
                    "passthrough.eac3": false,
                    "passthrough.truehd": false
                },
                "cec": {
                    "activatesource": true,
                    "enable": true,
                    "hdmiport": 0,
                    "poweroffonstandby": false,
                    "suspendonstandby": false,
                    "usekeyupdown": false,
                    "verbose_logging": false
                },
                "main": {
                    "allowBrowserZoom": true,
                    "alwaysOnTop": false,
                    "autodetectCertBundle": true,
                    "checkForUpdates": false,
                    "disablemouse": false,
                    "enableInputRepeat": true,
                    "enableMPV": true,
                    "enableWindowsMediaIntegration": true,
                    "enableWindowsTaskbarIntegration": true,
                    "forceAlwaysFS": false,
                    "forceFSScreen": "",
                    "fullscreen": true,
                    "hdmi_poweron": false,
                    "ignoreSSLErrors": false,
                    "layout": "desktop",
                    "logLevel": "debug",
                    "minimizeOnDefocus": false,
                    "sdlEnabled": true,
                    "showPowerOptions": true,
                    "useOpenGL": false,
                    "useSystemVideoCodecs": false,
                    "userWebClient": "${config.bcl.role.tv.jellyfinUrl}",
                    "webMode": "desktop"
                },
                "other": {
                    "other_conf": ""
                },
                "path": {
                    "startupurl_desktop": "bundled",
                    "startupurl_extension": "bundled"
                },
                "subtitles": {
                    "ass_scale_border_and_shadow": true,
                    "ass_style_override": "",
                    "background_color": "",
                    "background_transparency": "",
                    "border_color": "",
                    "border_size": -1,
                    "color": "",
                    "font": "sans-serif",
                    "placement": "",
                    "size": -1
                },
                "system": {
                    "lircd_enabled": false,
                    "smbd_enabled": false,
                    "sshd_enabled": false,
                    "systemname": "JellyfinDesktop"
                },
                "video": {
                    "allow_transcode_to_hevc": false,
                    "always_force_transcode": false,
                    "aspect": "normal",
                    "audio_delay.24hz": 0,
                    "audio_delay.25hz": 0,
                    "audio_delay.50hz": 0,
                    "audio_delay.normal": 0,
                    "cache": 500,
                    "debug.force_vo": "",
                    "default_playback_speed": 1,
                    "deinterlace": false,
                    "force_transcode_4k": false,
                    "force_transcode_av1": true,
                    "force_transcode_dovi": true,
                    "force_transcode_hdr": false,
                    "force_transcode_hevc": false,
                    "force_transcode_hi10p": false,
                    "hardwareDecoding": "enabled",
                    "prefer_transcode_to_h265": false,
                    "refreshrate.auto_switch": true,
                    "refreshrate.avoid_25hz_30hz": true,
                    "refreshrate.delay": 3,
                    "sync_mode": "audio"
                }
            },
            "version": 7
        }
      '';
    };
  })
  ];
}