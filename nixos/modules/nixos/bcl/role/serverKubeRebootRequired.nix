{ config, lib, pkgs, ... }:
let
  sentinelDirectory = "/run/kured";
  sentinelFile = "${sentinelDirectory}/reboot-required";

  # `system.autoUpgrade` stages the new generation with `boot`: it is not the running one until the node reboots.
  # A `switch` activates everything but a new kernel, initrd or kernel modules.
  updateRebootRequiredSentinel = pkgs.writeShellApplication {
    name = "kube-update-reboot-required-sentinel";
    runtimeInputs = [ pkgs.coreutils ];
    text = ''
      isRebootRequired() {
        [ "$(readlink -f /nix/var/nix/profiles/system)" != "$(readlink -f /run/current-system)" ] && return 0
        for part in initrd kernel kernel-modules; do
          [ "$(readlink -f "/run/booted-system/$part")" != "$(readlink -f "/run/current-system/$part")" ] && return 0
        done
        return 1
      }

      if isRebootRequired; then
        touch ${sentinelFile}
      else
        rm -f ${sentinelFile}
      fi
    '';
  };
in
{
  # The sentinel of kured (see kube/charts/app-kured): its presence asks the node to be drained and rebooted. Lives in a directory of its
  # own, as kured mounts the directory of the sentinel in its pod.
  config = lib.mkIf (config.bcl.role.name == "serverKube") {
    systemd.tmpfiles.rules = [ "d ${sentinelDirectory} 0755 root root -" ];

    systemd.services."kube-update-reboot-required-sentinel" = {
      description = "Tell kured whether the node has to be rebooted";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${updateRebootRequiredSentinel}/bin/kube-update-reboot-required-sentinel";
      };
    };

    systemd.timers."kube-update-reboot-required-sentinel" = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "1min";
        OnUnitActiveSec = "5min";
      };
    };
  };
}
