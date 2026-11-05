{ config, lib, ... }:
{
  options.bcl.role.nas.sftpUsers = lib.mkOption {
    default = { };
    description = ''
      SFTP-only users. Each user is public-key only, has no shell, and is
      chrooted in /nix/data/<name>. Writable data goes in /nix/data/<name>/data
      (the chroot root must stay root-owned).
    '';
    type = lib.types.attrsOf (lib.types.submodule {
      options.authorizedKeys = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        description = "SSH public keys allowed to log in as this user.";
      };
    });
  };

  config = lib.mkMerge [
    { bcl.role.knownRoles = [ "nas" ]; }
    (lib.mkIf (config.bcl.role.name == "nas") (
      let
        sftpUsers = config.bcl.role.nas.sftpUsers;
      in {

      security.sudo.wheelNeedsPassword = false;

      users.groups = { sftp-only = { }; } // lib.mapAttrs (_: _: { }) sftpUsers;

      users.users = lib.mapAttrs (name: u: {
        isSystemUser = true;
        group = name;
        extraGroups = [ "sftp-only" ];
        home = "/nix/data/${name}";
        shell = "/run/current-system/sw/bin/nologin";
        openssh.authorizedKeys.keys = u.authorizedKeys;
      }) sftpUsers;

      services.openssh.extraConfig = lib.mkIf (sftpUsers != { }) ''
        Match Group sftp-only
          ChrootDirectory /nix/data/%u
          ForceCommand internal-sftp -d /data
          AllowTcpForwarding no
          AllowAgentForwarding no
          X11Forwarding no
          PermitTTY no
      '';

      # sshd refuses a chroot directory that is not root-owned or is writable by
      # others, and applies the same check to EVERY parent component, so /nix/data
      # itself must be root:root and not group/world-writable too. The user's
      # writable area is the `data` subdirectory, which internal-sftp starts
      # in (-d /data).
      systemd.tmpfiles.rules = lib.optionals (sftpUsers != { }) (
        [ "d /nix/data 0755 root root -" "d /nix/data 0755 root root -" ]
        ++ lib.concatLists (lib.mapAttrsToList (name: _: [
          "d /nix/data/${name} 0755 root root -"
          "d /nix/data/${name}/data 0700 ${name} ${name} -"
        ]) sftpUsers)
      );

    }))
  ];
}
