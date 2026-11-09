{ config, lib, ... }:

let
  cfg = config.bcl.role.vmRestartRequired;
in
{
  options.bcl.role.vmRestartRequired.window = {
    startHour = lib.mkOption {
      type = lib.types.ints.between 0 23;
      default = 3;
      description = "Hour (local time, inclusive) from which the guest reboots when the host asks for a restart of the VM.";
    };
    endHour = lib.mkOption {
      type = lib.types.ints.between 0 23;
      default = 4;
      description = "Hour (local time, exclusive) from which the guest does not reboot anymore when the host asks for a restart of the VM.";
    };
  };

  # The host asks for a restart of the VM by creating /run/vm-restart-required (see `restartOnChange` in bcl/vm.nix). The kube nodes hand it
  # to kured (serverKubeRebootRequired.nix), the other guests have nothing to drain: they reboot in the window. The VM is stopped by the
  # reboot and started again by the host, with its new definition.
  config = lib.mkIf (
    config.bcl.role.name != "" && config.bcl.role.name != "serverKube" && builtins.elem "qemu-guest" config.bcl.hardware.commons
  ) {
    systemd.services.vm-restart-required = {
      description = "Reboot when the host asks for a restart of the VM, in the window";
      serviceConfig.Type = "oneshot";
      script = ''
        [ -e /run/vm-restart-required ] || exit 0
        h=$((10#$(date +%H)))
        ${if cfg.window.startHour < cfg.window.endHour
          then "[ \"$h\" -ge ${toString cfg.window.startHour} ] && [ \"$h\" -lt ${toString cfg.window.endHour} ] || exit 0"
          else "[ \"$h\" -ge ${toString cfg.window.startHour} ] || [ \"$h\" -lt ${toString cfg.window.endHour} ] || exit 0"}
        systemctl reboot
      '';
    };

    systemd.timers.vm-restart-required = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "10min";
        OnUnitActiveSec = "10min";
      };
    };
  };
}
