{ config, lib, pkgs, ... }:
{
  config = lib.mkIf (config.bcl.role.name != "") {
    boot.kernel.sysctl = {
      "fs.inotify.max_user_watches" = 1048576; # default: 8192
      "fs.inotify.max_user_instances" = 1024; # default: 128
      "fs.inotify.max_queued_events" = 32768; # default: 16384
    };
  };
}
