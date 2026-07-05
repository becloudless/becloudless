{ config, lib, pkgs, ... }:
let
  cfg = config.bcl.role.tv.screensaver;
in
{
  options.bcl.role.tv.screensaver = {
    immich = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Include photos/videos fetched from an Immich album in the screensaver playlist.";
      };
      albumId = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Immich album UUID to display as screensaver.";
      };
    };
    jellyfin.enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Include movies/shows backdrops fetched from Jellyfin in the screensaver playlist.";
    };
  };

  config = lib.mkIf (config.bcl.role.name == "tv" && (cfg.immich.enable || cfg.jellyfin.enable)) {
    environment.systemPackages = with pkgs; [ curl jq ];

    sops.secrets."users.tv.immich.apiKey" = lib.mkIf cfg.immich.enable {
      sopsFile = config.bcl.role.secretFile;
      owner = "tv";
    };

    sops.secrets."users.tv.jellyfin.apiKey" = lib.mkIf cfg.jellyfin.enable {
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
          mpv --fs --loop-playlist=inf --image-display-duration=30 --no-osd-bar --panscan=0 --scale=bilinear --video-unscaled=no --mute=yes --speed=0.5 --osd-playing-msg=\''${media-title} --osd-duration=3600000 --osd-font-size=12 --osd-align-x=left --osd-align-y=bottom "$PLAYLIST" &
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

    # Generate m3u playlist fragments per source, then combine them into the
    # final playlist so Immich and Jellyfin can be enabled independently
    # without one sync overwriting the other's entries.

    # Fragment with direct Immich URLs
    systemd.user.services."immich-photo-sync" = lib.mkIf cfg.immich.enable {
      path = with pkgs; [ curl jq bash coreutils ];
      script = ''
        set -euo pipefail
        set -x

        IMMICH_URL="https://immich.${config.bcl.global.domain}"
        IMMICH_API_KEY="$(cat ${config.sops.secrets."users.tv.immich.apiKey".path})"
        ALBUM_ID="${cfg.immich.albumId}"
        PLAYLIST_DIR="$HOME/.cache/screensaver.d"
        FRAGMENT="$PLAYLIST_DIR/immich.m3u"
        PLAYLIST="$HOME/.cache/screensaver.m3u"

        mkdir -p "$PLAYLIST_DIR"

        echo "Fetching asset list from album $ALBUM_ID..."
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
            done > "$FRAGMENT.tmp"
        mv "$FRAGMENT.tmp" "$FRAGMENT"

        {
          echo "#EXTM3U"
          cat "$PLAYLIST_DIR"/*.m3u 2>/dev/null | paste -d'\t' - - | shuf | tr '\t' '\n'
        } > "$PLAYLIST.tmp"
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

    # Fragment with direct Jellyfin backdrop URLs (movies + shows)
    systemd.user.services."jellyfin-backdrop-sync" = lib.mkIf cfg.jellyfin.enable {
      path = with pkgs; [ curl jq bash coreutils ];
      script = ''
        set -euo pipefail
        set -x

        JELLYFIN_URL="${config.bcl.role.tv.jellyfinUrl}"
        JELLYFIN_API_KEY="$(cat ${config.sops.secrets."users.tv.jellyfin.apiKey".path})"
        PLAYLIST_DIR="$HOME/.cache/screensaver.d"
        FRAGMENT="$PLAYLIST_DIR/jellyfin.m3u"
        PLAYLIST="$HOME/.cache/screensaver.m3u"

        mkdir -p "$PLAYLIST_DIR"

        echo "Fetching movies/shows backdrops from Jellyfin..."
        curl -sf \
          -H "X-Emby-Token: $JELLYFIN_API_KEY" \
          "$JELLYFIN_URL/Items?IncludeItemTypes=Movie,Series&Recursive=true&Fields=BackdropImageTags" \
          | jq -r '.Items[] | .Id as $id | .Name as $name | (.BackdropImageTags | length) as $count | range(0; $count) | "\($id)\t\($name)\t\(.)"' \
          | while IFS=$'\t' read -r item_id item_name tag_index; do
              echo "#EXTINF:-1,$item_name"
              echo "$JELLYFIN_URL/Items/$item_id/Images/Backdrop/$tag_index?api_key=$JELLYFIN_API_KEY"
            done > "$FRAGMENT.tmp"
        mv "$FRAGMENT.tmp" "$FRAGMENT"

        {
          echo "#EXTM3U"
          cat "$PLAYLIST_DIR"/*.m3u 2>/dev/null | paste -d'\t' - - | shuf | tr '\t' '\n'
        } > "$PLAYLIST.tmp"
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

    systemd.user.timers."immich-photo-sync" = lib.mkIf cfg.immich.enable {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "2min";
        OnUnitActiveSec = "1h";
        Persistent = true;
      };
    };

    systemd.user.timers."jellyfin-backdrop-sync" = lib.mkIf cfg.jellyfin.enable {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "2min";
        OnUnitActiveSec = "1h";
        Persistent = true;
      };
    };
  };
}
