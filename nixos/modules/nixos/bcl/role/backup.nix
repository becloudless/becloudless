{ config, lib, pkgs, ... }:
{
  options.bcl.role.backup.autoShutdown = lib.mkOption {
    type = lib.types.bool;
    default = true;
    description = "Power off the server after a period without SSH sessions, logged-in users or running disk scrubs.";
  };

  options.bcl.role.backup.sftpUsers = lib.mkOption {
    default = { };
    description = ''
      SFTP-only users (one per backup context). Each user is public-key only,
      has no shell, and is chrooted in /data/Backups/<name>. Writable data goes in
      /data/Backups/<name>/files (the chroot root must stay root-owned).
    '';
    type = lib.types.attrsOf (lib.types.submodule {
      options.authorizedKeys = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        description = "SSH public keys allowed to log in as this user.";
      };
    });
  };

  config = lib.mkMerge [
    { bcl.role.knownRoles = [ "backup" ]; }
    (lib.mkIf (config.bcl.role.name == "backup") (
      let
        sftpUsers = config.bcl.role.backup.sftpUsers;

        # Data pools backed by more than one physical disk (mergerfs pools).
        # A file written into the pool (e.g. gocryptfs.conf) only lands on
        # whichever single branch disk mergerfs picked, so it must be copied
        # to every backing disk to be readable when a disk is pulled/mounted
        # standalone.
        multiDiskData = lib.filterAttrs
          (_: dataCfg: dataCfg.sourceFoldersPattern != null || builtins.length dataCfg.sourceFolders > 1)
          config.bcl.data;

        syncGocryptfsConfScript = lib.concatStringsSep "\n" (lib.mapAttrsToList (name: dataCfg:
          let
            targets = if dataCfg.sourceFoldersPattern != null
              then dataCfg.sourceFoldersPattern
              else lib.concatMapStringsSep " " lib.escapeShellArg dataCfg.sourceFolders;
          in ''
            conf="${dataCfg.path}/gocryptfs.conf"
            if [ -f "$conf" ]; then
              for disk in ${targets}; do
                if [ -d "$disk" ] && ! cmp -s "$conf" "$disk/gocryptfs.conf" 2>/dev/null; then
                  echo "[sync-gocryptfs-conf] Copying gocryptfs.conf to $disk"
                  cp "$conf" "$disk/gocryptfs.conf"
                fi
              done
            else
              echo "[sync-gocryptfs-conf] No gocryptfs.conf found at ${dataCfg.path}, skipping ${name}"
            fi
          ''
        ) multiDiskData);

        # gocryptfs writes one "gocryptfs.diriv" (directory IV) file into EVERY
        # directory of the reverse view, not just the root, and each one only
        # lands on whichever single branch mergerfs' mkdir/create policy
        # picked. Walk the whole pool tree and mirror every diriv file.
        syncGocryptfsDirivScript = lib.concatStringsSep "\n" (lib.mapAttrsToList (name: dataCfg:
          let
            targets = if dataCfg.sourceFoldersPattern != null
              then dataCfg.sourceFoldersPattern
              else lib.concatMapStringsSep " " lib.escapeShellArg dataCfg.sourceFolders;
          in ''
            poolPath="${dataCfg.path}"
            find "$poolPath" -type f -name 'gocryptfs.diriv' -print0 | while IFS= read -r -d ''' f; do
              rel="''${f#$poolPath/}"
              for disk in ${targets}; do
                if [ -d "$disk" ]; then
                  destFile="$disk/$rel"
                  destDir="$(dirname "$destFile")"
                  if [ -d "$destDir" ] && [ ! -f "$destFile" ]; then
                    echo "[sync-gocryptfs-conf] Copying $rel to $disk"
                    cp "$f" "$destFile"
                  fi
                fi
              done
            done
          ''
        ) multiDiskData);
      in {

     security.sudo.wheelNeedsPassword = false;

      users.groups = { sftp-only = { }; } // lib.mapAttrs (_: _: { }) sftpUsers;

      users.users = lib.mapAttrs (name: u: {
        isSystemUser = true;
        group = name;
        extraGroups = [ "sftp-only" ];
        home = "/data/Backups/${name}";
        shell = "/run/current-system/sw/bin/nologin";
        openssh.authorizedKeys.keys = u.authorizedKeys;
      }) sftpUsers;

      services.openssh.extraConfig = lib.mkIf (sftpUsers != { }) ''
        Match Group sftp-only
          ChrootDirectory /data/Backups/%u
          ForceCommand internal-sftp
          AllowTcpForwarding no
          AllowAgentForwarding no
          X11Forwarding no
          PermitTTY no
      '';

      # The chroot directory must be root-owned and not writable by others,
      # so each user writes in its own `files` subdirectory.
      systemd.tmpfiles.rules = lib.optionals (sftpUsers != { }) (
        [ "d /data/Backups 0755 root root -" ]
        ++ lib.concatLists (lib.mapAttrsToList (name: _: [
          "d /data/Backups/${name} 0755 root root -"
          "d /data/Backups/${name}/files 0700 ${name} ${name} -"
        ]) sftpUsers)
      );

      environment.systemPackages = with pkgs; [
        mergerfs
      ];

      systemd.services."shutdown-when-inactive" = {
        path = with pkgs; [ iproute2 ];
        enable = config.bcl.role.backup.autoShutdown;
        script = ''
            count=0
            intervalSecond=10
            maxInterval=60
            while true; do
                ((count=$count+1))

                loggedInCount=$(who | wc -l)
                sshConnCount=$(ss -t -a | grep ssh | grep ESTAB | wc -l)

                scrubActive=0
                if systemctl list-units --type=service --state=running --no-legend 'disk-scrub-*.service' | grep -q .; then
                    scrubActive=1
                fi

                if [[ $loggedInCount -gt 0 ]] || [[ $sshConnCount -gt 0 ]] || [[ $scrubActive -eq 1 ]]; then
                    if [[ $count -gt 0 ]]; then
                        reason=""
                        if [[ $loggedInCount -gt 0 ]]; then reason+="logged-in users=$loggedInCount; "; fi
                        if [[ $sshConnCount -gt 0 ]]; then reason+="active ssh sessions=$sshConnCount; "; fi
                        if [[ $scrubActive -eq 1 ]]; then reason+="disk scrub in progress; "; fi
                        echo "Skipping auto-shutdown: $reason"
                    fi
                    count=0
                fi

                if [[ $count -gt $maxInterval ]]; then
                    echo "No connection since $((count*intervalSecond)) sec, powering off"
                    systemctl poweroff
                fi
                sleep $intervalSecond
            done
        '';
        wantedBy = ["multi-user.target"];
      };

      systemd.services."sync-gocryptfs-conf" = {
        description = "Copy each data pool's gocryptfs.conf and gocryptfs.diriv files onto every backing disk";
        after = [ "local-fs.target" ];
        path = with pkgs; [ diffutils ];
        serviceConfig = {
          Type = "oneshot";
        };
        script = syncGocryptfsConfScript + "\n" + syncGocryptfsDirivScript;
      };

      systemd.timers."sync-gocryptfs-conf" = {
        description = "Timer for sync-gocryptfs-conf";
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnCalendar = "weekly";
          Persistent = true;
        };
      };

    }))
  ];
}