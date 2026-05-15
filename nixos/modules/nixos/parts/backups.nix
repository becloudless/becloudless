{ config, lib, pkgs, ... }:
let
  cfg = config.bcl.backups;

  enabledBackups = lib.filterAttrs (_: b: b.enable) cfg;

  # Extract IP/hostname from "host:/path"
  targetHost = target: builtins.head (lib.splitString ":" target);

  mkBackupService = name: backup:
    let
      host       = targetHost backup.target;
      filterArgs = lib.concatMapStringsSep " " (f: "--filter=${lib.escapeShellArg f}") backup.sourceFilter;
    in {
      description = "Backup ${name}: ${backup.source} -> ${backup.target}";
      after    = [ "network-online.target" ];
      wants    = [ "network-online.target" ];
      serviceConfig = {
        Type = "oneshot";
        User = "root";
      };
      path = with pkgs; [ etherwake openssh rsync iputils ];
      script = ''
        set -euo pipefail

        ${lib.optionalString (backup.targetMac != null) ''
          echo "[backup-${name}] Waking up ${host} via WOL (${backup.targetMac})..."
          etherwake ${backup.targetMac}
        ''}

        echo "[backup-${name}] Waiting for SSH on ${host}..."
        timeout=300
        elapsed=0
        until ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o BatchMode=yes \
              root@${host} true 2>/dev/null; do
          if [ "$elapsed" -ge "$timeout" ]; then
            echo "[backup-${name}] Timeout waiting for SSH on ${host}" >&2
            exit 1
          fi
          sleep 5
          elapsed=$((elapsed + 5))
        done
        echo "[backup-${name}] ${host} is reachable via SSH"

        echo "[backup-${name}] Starting rsync..."
        rsync -avz --delete \
          ${filterArgs} \
          -e "ssh -o StrictHostKeyChecking=no" \
          "${backup.source}/" \
          "root@${backup.target}/"

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
        sourceFilter = [ "- *.tmp" ];
        target       = "192.168.40.49:/data/week";
        targetMac    = "00:d8:61:6f:f8:6e";
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

        sourceFilter = lib.mkOption {
          type        = lib.types.listOf lib.types.str;
          default     = [];
          description = "List of rsync --filter rules (e.g. [ \"- *.tmp\" \"+ important/\" ]).";
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
