{ inputs, config, lib, pkgs, ... }:
{
  options.bcl.tv = {
    audioType = lib.mkOption {
         type = lib.types.str;
         default = "basic";
      };
    audioDevice = lib.mkOption {
         type = lib.types.str;
         default = "auto";
      };
  };

  config = lib.mkIf (config.bcl.role.name == "tv") {
    bcl.boot.quiet = true;
    bcl.sound.enable = true;
    bcl.wm = {
      name = "dwm";
      user = "tv";
    };
    bcl.wifi.enable = true;

    security.sudo.wheelNeedsPassword = false;

    environment.systemPackages = with pkgs; [
      jellyfin-media-player
      xdotool # move mouse
      pulseaudio
    ];

    users.users.tv = {
      isNormalUser = true;
      group = "users";
    };


    systemd.tmpfiles.rules = [
      "d /nix/home/tv 0700 tv users"
    ];

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

          xrandr -r 24
          # TODO this is a hack
          pactl set-sink-volume @DEFAULT_SINK@ 100%
          pactl set-sink-volume alsa_output.pci-0000_00_0e.0.hdmi-stereo 100% # TODO

          # TODO wait for network
          # while ! ping -c 1 -W 1 192.168.40.12; do sleep 1; done;
          bash -c "while true; do jellyfinmediaplayer; sleep 5; done" &
          bash -c "sleep 20; xdotool mousemove 100 100; xdotool click 1; amixer set Master 95%;" &
        fi
      '';

      home.file.".local/share/jellyfinmediaplayer/jellyfinmediaplayer.conf".text = ''
        {
            "sections": {
                "appleremote": {
                    "emulatepht": true
                },
                "audio": {
                    "channels": "2.0",
                    "device": "${config.bcl.tv.audioDevice}",
                    "devicetype": "${config.bcl.tv.audioType}",
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
                    "alwaysOnTop": false,
                    "autodetectCertBundle": false,
                    "checkForUpdates": false,
                    "disablemouse": false,
                    "enableInputRepeat": true,
                    "enableWindowsMediaIntegration": true,
                    "enableWindowsTaskbarIntegration": true,
                    "forceAlwaysFS": false,
                    "forceExternalWebclient": false,
                    "forceFSScreen": "",
                    "fullscreen": false,
                    "hdmi_poweron": false,
                    "ignoreSSLErrors": false,
                    "layout": "desktop",
                    "logLevel": "debug",
                    "minimizeOnDefocus": false,
                    "sdlEnabled": true,
                    "showPowerOptions": true,
                    "useOpenGL": false,
                    "useSystemVideoCodecs": false,
                    "userWebClient": "https://jellyfin.bcl.io",
                    "webMode": "desktop"
                },
                "other": {
                    "other_conf": ""
                },
                "path": {
                    "startupurl_desktop": "bundled",
                    "startupurl_extension": "bundled"
                },
                "plugins": {
                    "skipintro": false
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
                    "systemname": "JellyfinMediaPlayer"
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
                    "force_transcode_4k": true,
                    "force_transcode_av1": true,
                    "force_transcode_dovi": true,
                    "force_transcode_hdr": true,
                    "force_transcode_hevc": true,
                    "force_transcode_hi10p": true,
                    "hardwareDecoding": "enabled",
                    "prefer_transcode_to_h265": false,
                    "refreshrate.auto_switch": true,
                    "refreshrate.avoid_25hz_30hz": true,
                    "refreshrate.delay": 3,
                    "sync_mode": "audio"
                }
            },
            "version": 6
        }
      '';

      home.persistence."/nix" = {
        directories = [
          ".local/share/jellyfinmediaplayer"
          ".local/share/Jellyfin Media Player"
          ".config/jellyfin.org"
        ];
      };
    };
  };
}