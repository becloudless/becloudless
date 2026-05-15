{ config, lib, pkgs, ... }:
let
  cfg = config.bcl.backups;

  enabledBackups = lib.filterAttrs (_: b: b.enable) cfg;

  # Extract IP/hostname and path from "host:/path"
  targetHost = target: builtins.head (lib.splitString ":" target);
  targetPath = target: builtins.elemAt (lib.splitString ":" target) 1;

  mkBackupService = name: backup:
    let
      host        = targetHost backup.target;
      path        = targetPath backup.target;
      # Build "-exclude-wildcard '!foo' -exclude-wildcard '!bar' -exclude-wildcard '*'"
      # so that only the listed patterns are included in the encrypted view.
      excludeArgs = lib.optionalString (backup.sourceIncludes != []) (
        "-exclude-wildcard '*' "
        + lib.concatMapStringsSep " " (p: "-exclude-wildcard ${lib.escapeShellArg "!${p}"}") backup.sourceIncludes
      );
    in {
      description = "Backup ${name}: ${backup.source} -> ${backup.target}";
      after    = [ "network-online.target" ];
      wants    = [ "network-online.target" ];
      serviceConfig = {
        Type = "oneshot";
        User = "root";
      };
      path = with pkgs; [ wol openssh rsync iputils gocryptfs fuse gawk util-linux ];
      script = ''
        set -euo pipefail
        set -x

        ${lib.optionalString (backup.targetMac != null) ''
          echo "[backup-${name}] Waking up ${host} via WOL (${backup.targetMac})..."
          wol ${backup.targetMac}
        ''}

        echo "[backup-${name}] Waiting for SSH on ${host}..."
        timeout=300
        elapsed=0
        until ssh -i /nix/etc/ssh/ssh_host_ed25519_key -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o BatchMode=yes \
              root@${host} true 2>/dev/null; do
          if [ "$elapsed" -ge "$timeout" ]; then
            echo "[backup-${name}] Timeout waiting for SSH on ${host}" >&2
            exit 1
          fi
          sleep 5
          elapsed=$((elapsed + 5))
        done
        echo "[backup-${name}] ${host} is reachable via SSH"

        PASS_FILE=$(mktemp /run/backup-${name}-pass-XXXXXX)
        MOUNT_DIR=$(mktemp -d /run/backup-${name}-XXXXXX)
        trap '
          echo "[backup-${name}] Unmounting $MOUNT_DIR"
          fusermount -u "$MOUNT_DIR" && rmdir "$MOUNT_DIR"
          rm -f "$PASS_FILE" "$RSYNC_STDERR"
        ' EXIT

        echo "[backup-${name}] Deriving gocryptfs passphrase from SSH key..."
        sha512sum /nix/etc/ssh/ssh_host_ed25519_key | awk '{print $1}' > "$PASS_FILE"

        echo "[backup-${name}] Mounting gocryptfs reverse view of ${backup.source} at $MOUNT_DIR..."
        if [ ! -f "${backup.source}/.gocryptfs.reverse.conf" ]; then
          echo "[backup-${name}] No gocryptfs config found, initialising..."
          gocryptfs -reverse -init -nosyslog -passfile "$PASS_FILE" "${backup.source}"
        fi
        gocryptfs -reverse -nosyslog -allow_other ${excludeArgs} -passfile "$PASS_FILE" "${backup.source}" "$MOUNT_DIR"

        echo "[backup-${name}] Starting rsync..."
        RSYNC_STDERR=$(mktemp /run/backup-${name}-rsync-err-XXXXXX)
        set +e
        rsync -avz --delete --ignore-errors \
          -e "ssh -i /nix/etc/ssh/ssh_host_ed25519_key -o StrictHostKeyChecking=no" \
          "$MOUNT_DIR/" \
          "root@${backup.target}/" \
          2>"$RSYNC_STDERR"
        RSYNC_EXIT=$?
        set -e
        # Ignore "failed to set times" only on the root destination folder
        # Ignore gocryptfs longname sidecar .name file readlink errors (known FUSE/gocryptfs reverse-mode quirk)
        REAL_ERRORS=$(grep -v 'failed to set times on "${path}/.": Operation not permitted' "$RSYNC_STDERR" \
          | grep -v 'readlink_stat(.*\.name.*): Operation not permitted' \
          || true)
        rm -f "$RSYNC_STDERR"
        if [ -n "$REAL_ERRORS" ]; then
          echo "$REAL_ERRORS" >&2
          exit $RSYNC_EXIT
        fi

        echo "[backup-${name}] Backup complete"
      '';
    };

  mkBackupTimer = name: backup: {
    description = "Timer for backup job ${name}";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = backup.timer;
      Persistent  = true;
    };
  };

in {
  options.bcl.backups = lib.mkOption {
    default     = {};
    description = "Named rsync backup job configurations with Wake-on-LAN support.";
    example = {
      week = {
        enable       = true;
        source       = "/data/Audio";
        sourceIncludes = [ "*.flac" "*.mp3" ];
        target       = "192.168.0.1:/data/week";
        targetMac    = "00:d8:61:6f:f4:6e";
        timer        = "Mon 02:00";
      };
    };
    type = lib.types.attrsOf (lib.types.submodule {
      options = {
        enable = lib.mkEnableOption "this backup job";

        source = lib.mkOption {
          type        = lib.types.str;
          description = "Local source directory to back up.";
        };

        sourceIncludes = lib.mkOption {
          type        = lib.types.listOf lib.types.str;
          default     = [];
          description = "Plaintext wildcard patterns to include in the gocryptfs reverse mount. Everything else is excluded. Implemented as: -exclude-wildcard '*' -exclude-wildcard '!pat1' -exclude-wildcard '!pat2'. Empty list includes everything.";
        };

        target = lib.mkOption {
          type        = lib.types.str;
          description = "Rsync destination in host:/path format (SSH transport).";
        };

        targetMac = lib.mkOption {
          type        = lib.types.nullOr lib.types.str;
          default     = null;
          description = "MAC address of the target for Wake-on-LAN. Null skips WOL.";
        };

        timer = lib.mkOption {
          type        = lib.types.str;
          description = "Systemd OnCalendar expression (e.g. \"Mon 02:00\", \"*-*-* 03:00:00\").";
        };
      };
    });
  };

  config = lib.mkIf (enabledBackups != {}) {
    systemd.services = lib.mapAttrs' (name: backup: {
      name  = "backup-${name}";
      value = mkBackupService name backup;
    }) enabledBackups;

    systemd.timers = lib.mapAttrs' (name: backup: {
      name  = "backup-${name}";
      value = mkBackupTimer name backup;
    }) enabledBackups;
  };
}
