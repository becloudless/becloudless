{ config, lib, pkgs, ... }:
let
  cfg = config.bcl.backups;

  enabledSources = lib.filterAttrs (_: b: b.enable) cfg;

  # Flatten sources+schedules into a list of { jobName, backup, scheduleName, schedule }
  # for every enabled schedule of every enabled source.
  flatSchedules = lib.concatLists (lib.mapAttrsToList (jobName: backup:
    lib.mapAttrsToList (scheduleName: schedule: {
      inherit jobName backup scheduleName schedule;
      fullName = "${jobName}-${scheduleName}";
    }) (lib.filterAttrs (_: s: s.enable) backup.schedules)
  ) enabledSources);

  # Extract IP/hostname from "host:/path"
  targetHost = target: builtins.head (lib.splitString ":" target);
  # Extract the remote path from "host:/path"
  targetPath = target: lib.concatStringsSep ":" (lib.tail (lib.splitString ":" target));

  mkBackupService = { fullName, backup, scheduleName, schedule, ... }:
    let
      host        = targetHost backup.target.address;
      remotePath  = "${targetPath backup.target.address}/${scheduleName}";
      name        = fullName;
      # gocryptfs's gitignore-style patterns are matched with a regex that is
      # implicitly recursive for directories (a pattern for "/Videos" also
      # matches everything under "/Videos"). That means naively negating an
      # ancestor directory (e.g. "!/Videos") to make a nested include like
      # "/Videos/Anime-Movies" reachable actually re-includes the ENTIRE
      # ancestor subtree (all of "/Videos", not just "Anime-Movies").
      # The fix is the standard gitignore "peeling" trick: for every proper
      # ancestor, re-include it (making it visible) and then immediately
      # re-exclude its (recursive) contents again with "ancestor/*", before
      # finally re-including the actual leaf path. Ancestors must be applied
      # shallowest-first so each level's re-exclude doesn't clobber a deeper
      # level's re-include.
      ancestorsOf = p:
        let
          segments = lib.filter (s: s != "") (lib.splitString "/" p);
        in lib.genList (i: "/" + lib.concatStringsSep "/" (lib.take (i + 1) segments)) (lib.max 0 (lib.length segments - 1));
      ancestorPaths = lib.sort
        (a: b: (lib.length (lib.splitString "/" a)) < (lib.length (lib.splitString "/" b)))
        (lib.unique (lib.concatMap ancestorsOf schedule.sourceIncludes));
      ancestorArgs = lib.concatMapStringsSep " "
        (a: "-exclude-wildcard ${lib.escapeShellArg "!${a}"} -exclude-wildcard ${lib.escapeShellArg "${a}/*"}")
        ancestorPaths;
      # Build "-exclude-wildcard '*' -exclude-wildcard '!foo' ..."
      # so that only the listed patterns are included in the encrypted view.
      # ".gocryptfs.reverse.conf" (the reverse-mode config file, stored as a
      # real plaintext file at the root of the source) must always be kept:
      # gocryptfs applies excludes to the plaintext tree BEFORE renaming it to
      # "gocryptfs.conf" in the encrypted view, so without this it would get
      # filtered out by the "*" exclude and never make it into the rsynced
      # backup, breaking mounting on the target.
      excludeArgs = lib.optionalString (schedule.sourceIncludes != []) (
        "-exclude-wildcard '*' "
        + (lib.optionalString (ancestorArgs != "") (ancestorArgs + " "))
        + lib.concatMapStringsSep " " (p: "-exclude-wildcard ${lib.escapeShellArg "!${p}"}") schedule.sourceIncludes
        + " -exclude-wildcard '!/.gocryptfs.reverse.conf'"
      );
      fullTarget = "${host}:${remotePath}";
    in {
      description = "Backup ${name}: ${backup.source} -> ${fullTarget}";
      after    = [ "network-online.target" ];
      wants    = [ "network-online.target" ];
      startLimitIntervalSec = 900;
      startLimitBurst = 3;
      serviceConfig = {
        Type = "oneshot";
        User = "root";
        Restart = "on-failure";
        RestartSec = "30s";
      };
      path = with pkgs; [ wol openssh rsync iputils gocryptfs fuse gawk util-linux ];
      script = ''
        set -euo pipefail
        set -x

        ${lib.optionalString (backup.target.mac != null) ''
          echo "[backup-${name}] Waking up ${host} via WOL (${backup.target.mac})..."
          wol ${backup.target.mac}
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

        echo "[backup-${name}] Checking that target folder ${remotePath} exists on ${host}..."
        if ! ssh -i /nix/etc/ssh/ssh_host_ed25519_key -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o BatchMode=yes \
              root@${host} "[ -d ${lib.escapeShellArg remotePath} ]"; then
          echo "[backup-${name}] Target folder ${remotePath} does not exist on ${host}, aborting" >&2
          exit 1
        fi

        PASS_FILE=$(mktemp /run/backup-${name}-pass-XXXXXX)
        MOUNT_DIR=$(mktemp -d /run/backup-${name}-XXXXXX)
        trap '
          echo "[backup-${name}] Unmounting $MOUNT_DIR"
          fusermount -u "$MOUNT_DIR" && rmdir "$MOUNT_DIR"
          rm -f "$PASS_FILE"
        ' EXIT

        echo "[backup-${name}] Deriving gocryptfs passphrase from SSH key..."
        # Trim leading/trailing whitespace (blank lines, trailing newline, ...)
        # before hashing, so incidental differences in the on-disk key file
        # don't change the derived passphrase. The "bcl" CLI trims identity
        # bytes the same way before hashing, so both sides stay in sync.
        awk 'BEGIN{RS="\0"} { gsub(/^[[:space:]]+/, ""); gsub(/[[:space:]]+$/, ""); printf "%s", $0 }' \
          /nix/etc/ssh/ssh_host_ed25519_key | sha512sum | awk '{print $1}' > "$PASS_FILE"

        echo "[backup-${name}] Mounting gocryptfs reverse view of ${backup.source} at $MOUNT_DIR..."
        if [ ! -f "${backup.source}/.gocryptfs.reverse.conf" ]; then
          echo "[backup-${name}] No gocryptfs config found, initialising..."
          gocryptfs -reverse -init -nosyslog -passfile "$PASS_FILE" "${backup.source}"
        fi
        gocryptfs -reverse -nosyslog -allow_other ${excludeArgs} -passfile "$PASS_FILE" "${backup.source}" "$MOUNT_DIR"

        echo "[backup-${name}] Starting rsync..."
        rsync -avzO --delete --max-alloc=0 \
          -e "ssh -i /nix/etc/ssh/ssh_host_ed25519_key -o StrictHostKeyChecking=no -o ConnectTimeout=10 -o ServerAliveInterval=15 -o ServerAliveCountMax=3" \
          "$MOUNT_DIR/" \
          "root@${fullTarget}/"

        echo "[backup-${name}] Backup complete"
      '';
    };

  mkBackupTimer = { fullName, schedule, ... }: {
    description = "Timer for backup job ${fullName}";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = schedule.timer;
      Persistent  = true;
    };
  };

in {
  options.bcl.backups = lib.mkOption {
    default     = {};
    description = "Named rsync backup source configurations with Wake-on-LAN support. Each source can have multiple named schedules, each backing up to \"<target>/<scheduleName>\" on its own timer.";
    example = {
      data = {
        enable         = true;
        source         = "/data/Audio";
        sourceIncludes = [ "*.flac" "*.mp3" ];
        target = {
          address = "192.168.0.1:/data";
          mac     = "00:d8:61:6f:f4:6e";
        };
        schedules = {
          week  = { timer = "Mon 02:00"; };
          month = { timer = "*-*-1 02:00"; sourceIncludes = [ "*.flac" ]; };
        };
      };
    };
    type = lib.types.attrsOf (lib.types.submodule ({ config, ... }: {
      options = {
        enable = lib.mkEnableOption "this backup source";

        source = lib.mkOption {
          type        = lib.types.str;
          description = "Local source directory to back up.";
        };

        sourceIncludes = lib.mkOption {
          type        = lib.types.listOf lib.types.str;
          default     = [];
          description = "Default plaintext wildcard patterns to include in the gocryptfs reverse mount, used by any schedule that doesn't set its own sourceIncludes. Everything else is excluded. Implemented as: -exclude-wildcard '*' -exclude-wildcard '!pat1' -exclude-wildcard '!pat2'. Empty list includes everything.";
        };

        target = lib.mkOption {
          description = "Rsync destination for this backup source, with optional Wake-on-LAN.";
          type = lib.types.submodule {
            options = {
              address = lib.mkOption {
                type        = lib.types.str;
                description = "Rsync destination base in host:/path format (SSH transport). Each schedule backs up to \"<address>/<scheduleName>\".";
              };

              mac = lib.mkOption {
                type        = lib.types.nullOr lib.types.str;
                default     = null;
                description = "MAC address of the target for Wake-on-LAN. Null skips WOL.";
              };
            };
          };
        };

        schedules = lib.mkOption {
          default     = {};
          description = "Named schedules for this backup source, each running on its own timer.";
          type = lib.types.attrsOf (lib.types.submodule {
            options = {
              enable = lib.mkEnableOption "this schedule" // { default = true; };

              timer = lib.mkOption {
                type        = lib.types.str;
                description = "Systemd OnCalendar expression (e.g. \"Mon 02:00\", \"*-*-* 03:00:00\").";
              };

              sourceIncludes = lib.mkOption {
                type        = lib.types.listOf lib.types.str;
                default     = config.sourceIncludes;
                description = "Plaintext wildcard patterns to include in the gocryptfs reverse mount for this schedule. Defaults to the source's sourceIncludes. Everything else is excluded. Implemented as: -exclude-wildcard '*' -exclude-wildcard '!pat1' -exclude-wildcard '!pat2'. Empty list includes everything.";
              };
            };
          });
        };
      };
    }));
  };

  config = lib.mkIf (flatSchedules != []) {
    systemd.services = builtins.listToAttrs (map (e: {
      name  = "backup-${e.fullName}";
      value = mkBackupService e;
    }) flatSchedules);

    systemd.timers = builtins.listToAttrs (map (e: {
      name  = "backup-${e.fullName}";
      value = mkBackupTimer e;
    }) flatSchedules);
  };
}
