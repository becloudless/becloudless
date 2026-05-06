{ config, lib, pkgs, ...}:
{
  services.usbguard = {
    enable = true;
    presentDevicePolicy = lib.mkDefault "keep";
  };

  # All declared users can handle USB access
  services.usbguard.IPCAllowedUsers = lib.attrNames config.bcl.users.users;

  # Start usbguard-notifier for every bcl user when they open a graphical session
  home-manager.users = lib.mapAttrs (_: _: { ... }: {
    systemd.user.services.usbguard-notifier = {
      Unit = {
        Description = "USBGuard notification daemon";
        PartOf = [ "graphical-session.target" ];
        After = [ "graphical-session.target" ];
      };
      Service = {
        ExecStart = "${pkgs.usbguard-notifier}/bin/usbguard-notifier";
        Restart = "on-failure";
      };
      Install.WantedBy = [ "graphical-session.target" ];
    };
  }) config.bcl.users.users;
}
