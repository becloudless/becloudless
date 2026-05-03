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
    environment.systemPackages = with pkgs; [ feh curl jq ];

    sops.secrets."users.tv.immich.apiKey" = {
      sopsFile = config.bcl.role.secretFile;
      owner = "tv";
    };

    systemd.user.services."screensaver" = {
      enable = true;
      path = with pkgs; [ bash feh procps ];
      script = ''
        set -x

        PHOTO_DIR="$HOME/.cache/screensaver-photos"

        function disableScreensaver {
          pid=$(pgrep -f feh || true)
          [ -z "$pid" ] || kill $pid
        }

        function displayScreensaver {
          disableScreensaver
          if [ -z "$(ls -A "$PHOTO_DIR" 2>/dev/null)" ]; then
            echo "No photos available in $PHOTO_DIR, waiting for sync..."
            return
          fi
          feh --recursive --randomize --full-screen -Z --slideshow-delay 30 --hide-pointer --draw-tinted -e yudit/20 --info "echo '%n'" "$PHOTO_DIR" &
        }

        ############################
        sleep 5
        displayScreensaver
        tail -fn0 ~/.local/share/jellyfin-desktop/profiles/b6a136dc17a44b32a63eed3507a6f2d0/logs/jellyfin-desktop.log \
          | grep --line-buffered "Entering state:" \
          | while read line; do
              state=$(echo $line | sed 's/.* - Entering state: \([a-z]*\)/\1/')
              case $state in
                buffering) disableScreensaver;;
                playing) disableScreensaver;;
                paused) displayScreensaver;;
                canceled) displayScreensaver;;
                finished) displayScreensaver;;
                *) echo "Unknown state $state";;
              esac
            done
      '';
      after = [ "graphical-session-pre.target" "immich-photo-sync.service" ];
      partOf = [ "graphical-session.target" ];
      wantedBy = [ "graphical-session.target" ];
      serviceConfig = {
        Restart = "on-failure";
        RestartSec = 10;
      };
    };

    # Sync photos from an Immich album to a local cache directory
    systemd.user.services."immich-photo-sync" = {
      path = with pkgs; [ curl jq bash ];
      script = ''
        set -euo pipefail
        set -x

        IMMICH_URL="https://immich.${config.bcl.global.domain}"
        IMMICH_API_KEY="$(cat ${config.sops.secrets."users.tv.immich.apiKey".path})"
        ALBUM_ID="${cfg.albumId}"
        PHOTO_DIR="$HOME/.cache/screensaver-photos"

        mkdir -p "$PHOTO_DIR"

        echo "Fetching asset list from album $ALBUM_ID..."
        assets=$(curl -sf \
          -H "x-api-key: $IMMICH_API_KEY" \
          "$IMMICH_URL/api/albums/$ALBUM_ID" \
          | jq -r '.assets[] | [.id, .originalFileName] | @tsv')

        # Track current IDs to remove stale photos
        current_ids=""

        while IFS=$'\t' read -r asset_id original_name; do
          ext="''${original_name##*.}"
          dest="$PHOTO_DIR/''${asset_id}.''${ext}"
          current_ids="$current_ids $asset_id"
          if [ ! -f "$dest" ]; then
            echo "Downloading $original_name ($asset_id)..."
            curl -sf \
              -H "x-api-key: $IMMICH_API_KEY" \
              "$IMMICH_URL/api/assets/$asset_id/thumbnail?size=preview" \
              -o "$dest" || echo "Failed to download $asset_id, skipping."
          fi
        done <<< "$assets"

        # Remove photos no longer in the album
        for f in "$PHOTO_DIR"/*; do
          [ -f "$f" ] || continue
          fid="''${f##*/}"
          fid="''${fid%%.*}"
          if ! echo "$current_ids" | grep -qw "$fid"; then
            echo "Removing stale photo $f"
            rm -f "$f"
          fi
        done

        echo "Sync complete. $(ls "$PHOTO_DIR" | wc -l) photos available."
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
