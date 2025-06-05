{ config, lib, ... }:

{
  config = lib.mkIf config.bcl.role.enable {
    environment.persistence."/nix" = {
      hideMounts = true;
      directories = [
        "/var/lib/nixos"
        "/var/lib/libvirt"
        "/var/log"
        "/var/lib/systemd/coredump"
        "/var/lib/systemd/timers"       # keep last run of timers units, even when poweroff
        "/root/.cache"

        { directory = "/var/db/sudo/lectured"; mode = "u=rwx,g=,o="; }
        # { directory = "/var/lib/colord"; user = "colord"; group = "colord"; mode = "u=rwx,g=rx,o="; }
      ];
      files = [
        "/etc/machine-id"
        "/var/lib/systemd/random-seed"
      ];
    };
  };
}
