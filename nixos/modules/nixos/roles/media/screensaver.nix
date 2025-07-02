{ config, lib, pkgs, ... }:
{
  config = lib.mkIf (config.bcl.role.name == "media") {

    environment.systemPackages = with pkgs; [
      sshfs-fuse
      feh
    ];

    systemd.user.services."screensaver" = {
      enable = true;
      path = with pkgs; [
        bash
        feh
        procps
      ];
      script = ''
        set -x

        function disableScreensaver {
          pid=$(pgrep -f feh || true)
          [ -z "$pid" ] || kill $pid
        }

        function displayScreensaver2 {
          disableScreensaver
          feh --recursive --randomize --full-screen -Z --slideshow-delay 30 --hide-pointer  --draw-tinted -e yudit/20 --info "echo '%n'" /data/image &
        }

        function displayScreensaver {
          disableScreensaver
          feh --recursive --randomize --full-screen -Z --slideshow-delay 30 --hide-pointer  --draw-tinted -e yudit/20 --info "echo '%n'" /data/image &
        }

        ############################
        sleep 5
        if [ -z "$( ls -A '/data' )" ]; then
          echo "Data is not mounted"
          exit 1
        fi

        displayScreensaver
        tail -fn0 ~/.local/share/jellyfinmediaplayer/logs/jellyfinmediaplayer.log \
          | grep --line-buffered "Entering state:" \
          | while read line; do
              state=$(echo $line | sed 's/.* - Entering state: \([a-z]*\)/\1/')
              case $state in
                buffering) disableScreensaver;;
                playing) disableScreensaver;;
                paused) displayScreensaver2;;
                canceled) displayScreensaver;;
                finished) displayScreensaver;;
                *) echo "Unkown state $state";;
              esac
            done
      '';
      after = [ "graphical-session-pre.target" ];
      partOf = [ "graphical-session.target" ];
      wantedBy = [ "graphical-session.target" ];
      serviceConfig = {
        Restart = "on-failure";
        RestartSec = 10;
      };
    };

    programs.fuse.userAllowOther = true;

    # .mount dynamic sytemd units from fstab cannot be setup to have access to openssl 
    # Path on .mount systemd units cannot be configured to have access to openssl
    systemd.services."data" = {
      path = with pkgs; [
        sshfs-fuse
        openssl
      ];
      script = ''
        mkdir -p /data
        ${pkgs.sshfs-fuse}/bin/sshfs -f -o allow_other,reconnect,ServerAliveInterval=15,ServerAliveCountMax=3 media.bcl.io:/ /data
      '';
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];
    };

    programs.ssh = {
      extraConfig = ''
        Host media.bcl.io
          User media
          IdentityFile /nix/etc/ssh/ssh_host_ed25519_key
          ProxyCommand /bin/sh -c "openssl s_client -servername ssh-%h -connect ssh-%h:443 -quiet -verify_quiet -verify_return_error 2> /dev/null"
      '';
      knownHosts = {
        "media.bcl.io".publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHxQyNqTdKQwVwp4mNGuYpodwZrftyug5JMwgGAsZ74N";
      };
    };
  };
}
