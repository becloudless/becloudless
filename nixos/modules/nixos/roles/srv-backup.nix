{ config, lib, pkgs, ... }:

{
  config = lib.mkIf (config.bcl.role.name == "srv-backup") {

    users.users.root = {
      hashedPassword = "$6$Y0kZdbKBqDOGlhSz$g4vfELVfnOPnStYEMHm0zpcNV0fEUQe3at5t1nO6dhDk0wS1OpyzI67l3Apb5ZsWGmsQtSrfTkEvcwzJLhAP1.";
      openssh.authorizedKeys.keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIK4m0EgFUcJGb3GNfoTLgPG0KA6n4QQQl3/ZRE1iC85Q backup"
      ];
    };

    security.sudo.wheelNeedsPassword = false;

    environment.systemPackages = with pkgs; [
      file # needed for disk bay location
      mergerfs
    ];


    systemd.services."shutdown-when-inactive" = {
      path = with pkgs; [ iproute2 ];
      enable = true;
      script = ''
          count=0
          intervalSecond=10
          maxInterval=60
          while true; do
              ((count=$count+1))
              if [[ $(who | wc -l) -gt 0 ]] || [[ $(ss -t -a | grep ssh | grep ESTAB | wc -l) -gt 0 ]]; then
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

    services.udev.extraRules = ''
        # spin down after 12min
        ACTION=="add", SUBSYSTEM=="block", KERNEL=="sd*[!0-9]", RUN+="${pkgs.hdparm}/sbin/hdparm -S144 /dev/\$kernel"
      '';

    environment.etc = {
      "disk-bay-location" = {
        mode = "0700";
        text = ''
          #!/usr/bin/env bash
          set -e
          target=$1
          [ "$(file -b "$target")" = "directory" ] && target=$(lsblk -no pkname $(df -P "$target" | awk 'END{print $1}'))
          path=$(find /dev/disk/by-path -exec sh -c "readlink -f {} | grep -q  $target\$ && echo {}" \;)
          cat /etc/disk-bay | grep "$${path%*-part?}" | cut -f1 -d=
        '';
      };

    };

  };

}
