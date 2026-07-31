{ config, lib, pkgs, ... }:
let
  cfg = config.bcl.role.tv.miracast;
in
{
  options.bcl.role.tv.miracast = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Whether to enable the Miracast (Wi-Fi Display) receiver, to cast
        from Android devices without Google/Chromecast.

        All wireless network interfaces are auto-detected (no interface
        name needs to be configured) and handed over entirely to
        MiracleCast's own Wi-Fi Direct wpa_supplicant instance, so they can
        no longer be used at the same time to join a regular Wi-Fi network
        (most wifi hardware/drivers can't do STA + P2P-GO concurrently via
        a single managed wpa_supplicant, and NetworkManager is told to stop
        managing wifi devices entirely). Use Ethernet for the host's normal
        network connectivity (e.g. to Jellyfin) if this is enabled.
      '';
    };
  };

  config = lib.mkIf (config.bcl.role.name == "tv" && cfg.enable) {
    # Tag every wireless network interface with the "miracle" udev tag, so
    # miracle-wifid (built with rely-udev=true) auto-manages all of them
    # without needing a hardcoded interface name. "wireless" is the
    # standard sysfs marker for a wifi device (present at
    # /sys/class/net/<iface>/wireless), the same test used by miraclecast's
    # own res/miracle-utils.sh find_wireless_network_interfaces helper.
    services.udev.extraRules = ''
      SUBSYSTEM=="net", ACTION=="add|change", TEST=="wireless", TAG+="miracle"
    '';

    # Let miracle-wifid own all wifi interfaces exclusively: NetworkManager
    # must not also try to manage/associate them.
    networking.networkmanager.unmanaged = [ "type:wifi" ];

    # dbus policy allowing org.freedesktop.miracle.wifi (bundled in the package).
    services.dbus.packages = [ pkgs.miraclecast ];

    environment.systemPackages = [ pkgs.miraclecast ];

    # Auto-run the sink on link "1" as soon as sinkctl starts, so no manual
    # interaction is needed. This assumes the host has a single wireless
    # interface (the common case for a TV box) - with several wifi
    # interfaces, additional links "2", "3", etc. would also appear and
    # would need to be run explicitly. Also auto-accepts incoming Wi-Fi
    # Direct connections (built-in miraclecast behaviour) with no PIN/
    # confirmation - any nearby device can cast to this TV.
    environment.etc."miraclecastrc".text = ''
      [sinkctl]
      autocmd=run 1
    '';

    systemd.services.miraclecast-wifid = {
      description = "MiracleCast Wi-Fi Display (P2P) management daemon";
      after = [ "dbus.service" ];
      wants = [ "dbus.service" ];
      wantedBy = [ "multi-user.target" ];
      path = [ pkgs.wpa_supplicant pkgs.miraclecast ];
      serviceConfig = {
        # No --interface flag: miracle-wifid auto-manages every interface
        # tagged "miracle" by the udev rule above.
        ExecStart = "${pkgs.miraclecast}/bin/miracle-wifid";
        Restart = "on-failure";
        RestartSec = "2s";
      };
    };

    systemd.services.miraclecast-sinkctl = {
      description = "MiracleCast Wi-Fi Display sink (renders incoming casts on the tv session)";
      after = [ "miraclecast-wifid.service" ];
      wants = [ "miraclecast-wifid.service" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        ExecStart = pkgs.writeShellScript "miraclecast-sinkctl-start" ''
          set -eu
          runtime_dir="/run/user/$(${pkgs.coreutils}/bin/id -u tv)"

          # Wait for the tv user's Wayland compositor (sway) to be up, so
          # miracle-gst has somewhere to render the incoming video into.
          until lock=$(${pkgs.coreutils}/bin/ls "$runtime_dir"/wayland-*.lock 2>/dev/null | head -n1); do
            sleep 1
          done

          export XDG_RUNTIME_DIR="$runtime_dir"
          export WAYLAND_DISPLAY="$(${pkgs.coreutils}/bin/basename "$lock" .lock)"

          exec ${pkgs.miraclecast}/bin/miracle-sinkctl
        '';
        Restart = "on-failure";
        RestartSec = "2s";
      };
    };
  };
}
