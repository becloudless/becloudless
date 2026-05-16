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

    })
  ];
}