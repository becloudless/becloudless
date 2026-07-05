{ config, lib, pkgs, ... }:
let
  cfg = config.bcl.role.tv.screensaver;
in
{
  options.bcl.role.tv.screensaver = {
    albumId = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Immich album UUID to display as screensaver. Feature is disabled when null.";
    };
  };

  config = lib.mkIf (config.bcl.role.name == "tv" && cfg.albumId != null) {
    environment.systemPackages = with pkgs; [ curl jq ];

    sops.secrets."users.tv.immich.apiKey" = {
      sopsFile = config.bcl.role.secretFile;
      owner = "tv";
    };

    systemd.user.services."screensaver" = {
      enable = true;
      path = with pkgs; [ bash mpv procps ];
      script = ''
        set -x

        PLAYLIST="$HOME/.cache/screensaver.m3u"

        function disableScreensaver {
          pid=$(pgrep -f mpv || true)
          [ -z "$pid" ] || kill $pid
        }

        function displayScreensaver {
          disableScreensaver
          if [ ! -s "$PLAYLIST" ] 2>/dev/null; then
            echo "No playlist available at $PLAYLIST, waiting for sync..."
            return
          fi
          mpv --fs --loop-playlist=inf --shuffle --image-display-duration=30 --no-osd-bar --panscan=0 --scale=bilinear --video-unscaled=no --mute=yes --speed=0.5 --osd-playing-msg=\''${media-title} --osd-duration=3600000 --osd-font-size=12 "$PLAYLIST" &
        }

        ############################
        sleep 5
        displayScreensaver
        tail -fn0 ~/.config/jellyfin-desktop/jellyfin-desktop.log \
          | grep --line-buffered "Firing signal:" \
          | while read line; do
              state=$(echo $line | sed 's/.*Firing signal: \([a-z]*\).*/\1/')
              case $state in
                playing) disableScreensaver;;
                canceled) displayScreensaver;;
                *) echo "Unknown state $state";;
              esac
            done
      '';
      wantedBy = [];
      serviceConfig = {
        Restart = "on-failure";
        RestartSec = 10;
        Environment = "DISPLAY=:0";
      };
    };

    # Generate m3u playlist with direct Immich URLs
    systemd.user.services."immich-photo-sync" = {
      path = with pkgs; [ curl jq bash coreutils ];
      script = ''
        set -euo pipefail
        set -x

        IMMICH_URL="https://immich.${config.bcl.global.domain}"
        IMMICH_API_KEY="$(cat ${config.sops.secrets."users.tv.immich.apiKey".path})"
        ALBUM_ID="${cfg.albumId}"
        PLAYLIST="$HOME/.cache/screensaver.m3u"

        mkdir -p "$(dirname "$PLAYLIST")"

        echo "Fetching asset list from album $ALBUM_ID..."
        echo "#EXTM3U" > "$PLAYLIST.tmp"
        curl -sf \
          -H "x-api-key: $IMMICH_API_KEY" \
          "$IMMICH_URL/api/albums/$ALBUM_ID" \
          | jq -r '.assets[] | [.id, .type, (.fileCreatedAt // .localDateTime // "")] | @tsv' \
          | while IFS=$'\t' read -r asset_id asset_type asset_date; do
              date_only="''${asset_date%%T*}"
              echo "#EXTINF:-1,$date_only"
              if [ "$asset_type" = "VIDEO" ]; then
                echo "$IMMICH_URL/api/assets/$asset_id/video/playback?apiKey=$IMMICH_API_KEY"
              else
                echo "$IMMICH_URL/api/assets/$asset_id/original?apiKey=$IMMICH_API_KEY"
              fi
            done >> "$PLAYLIST.tmp"
        mv "$PLAYLIST.tmp" "$PLAYLIST"

        echo "Playlist updated with $(grep -c http "$PLAYLIST") entries."
      '';
      serviceConfig = {
        Type = "oneshot";
      };
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "default.target" ];
    };

    systemd.user.timers."immich-photo-sync" = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "2min";
        OnUnitActiveSec = "1h";
        Persistent = true;
      };
    };
  };
}
