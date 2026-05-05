{ inputs, config, lib, pkgs, ... }:
{
  config = lib.mkMerge [
    { bcl.role.knownRoles = [ "backup" ]; }
    (lib.mkIf (config.bcl.role.name == "backup") {

     security.sudo.wheelNeedsPassword = false;

      environment.systemPackages = with pkgs; [
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

    })
  ];
}