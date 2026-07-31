{ config, lib, pkgs, ... }:
let
  cfg = config.bcl.role.tv.miracast;
  global = config.bcl.global;
  pskSecretName = "networking.wireless.${cfg.network.ssid}.password";
in
{
  options.bcl.role.tv.miracast = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Whether to enable the Miracast (Wi-Fi Display) receiver, to cast
        from Android devices without Google/Chromecast.

        This runs concurrently with normal Wi-Fi networking on the SAME
        physical radio (`interface`): the same trick Android itself uses to
        keep your phone's own Wi-Fi connected while it casts. This is
        possible because Wi-Fi Direct (P2P) group formation is handled by
        the wpa_supplicant instance that already owns the "station" (STA)
        interface - it dynamically spins up virtual P2P-Device/P2P-GO
        interfaces on the same phy alongside the normal AP association,
        rather than needing an entirely separate radio. Confirm your
        hardware supports this via `iw phy <phy> info`: look for a "valid
        interface combinations" entry listing "managed" together with
        "P2P-client, P2P-GO" allowing more than 1 total interface (checked
        on an Intel AX201: supported).

        Since MiracleCast's own `miracle-wifid` always spawns its own
        wpa_supplicant instance and takes exclusive ownership of whatever
        interface it's given, `interface` is unmanaged by NetworkManager
        and, instead, normal STA networking on it is achieved by injecting
        an infrastructure network into that SAME wpa_supplicant instance at
        runtime (via its control socket) and running dhcpcd scoped to just
        that interface.
      '';
    };
    interface = lib.mkOption {
      type = lib.types.str;
      description = ''
        Name of the wifi network interface (e.g. "wlan0") shared between
        normal station networking and Miracast's Wi-Fi Direct receiver.
      '';
    };
    network = {
      ssid = lib.mkOption {
        type = lib.types.str;
        description = ''
          SSID of the Wi-Fi network `interface` should associate to for
          normal networking (e.g. to reach Jellyfin), concurrently with
          acting as a Miracast receiver.
        '';
      };
    };
  };

  config = lib.mkIf (config.bcl.role.name == "tv" && cfg.enable) {
    # miracle-wifid needs to be the sole owner of this interface's
    # wpa_supplicant (it always spawns/manages its own instance), so
    # NetworkManager must not also try to manage/associate it.
    networking.networkmanager.unmanaged = [ "interface-name:${cfg.interface}" ];

    # DHCP client for the STA role on `interface`, scoped to just this
    # interface so it doesn't interfere with NetworkManager handling
    # everything else (e.g. Ethernet).
    networking.dhcpcd.allowInterfaces = [ cfg.interface ];

    sops.secrets.${pskSecretName} = lib.mkIf (global.secretFile != null) {
      sopsFile = global.secretFile;
    };

    # Tag the shared interface with "miracle", so miracle-wifid (built with
    # rely-udev=true) manages it.
    services.udev.extraRules = ''
      SUBSYSTEM=="net", ACTION=="add|change", NAME=="${cfg.interface}", TAG+="miracle"
    '';

    # dbus policy allowing org.freedesktop.miracle.wifi (bundled in the package).
    services.dbus.packages = [ pkgs.miraclecast ];

    environment.systemPackages = [ pkgs.miraclecast ];

    # Auto-run the sink on link "1" (the only managed link, since a single
    # interface is shared) as soon as sinkctl starts, so no manual
    # interaction is needed. Also auto-accepts incoming Wi-Fi Direct
    # connections (built-in miraclecast behaviour) with no PIN/confirmation
    # - any nearby device can cast to this TV.
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
        ExecStart = "${pkgs.miraclecast}/bin/miracle-wifid --interface=${cfg.interface}";
        Restart = "on-failure";
        RestartSec = "2s";
      };
    };

    # Concurrently join the normal Wi-Fi network on the SAME interface, by
    # talking to the wpa_supplicant instance that miracle-wifid itself
    # spawned (via its standard per-interface ctrl_interface socket at
    # /run/miracle/wifi/<interface>) rather than running a second,
    # conflicting wpa_supplicant. wpa_supplicant fully supports handling a
    # normal infrastructure association and Wi-Fi Direct group formation at
    # the same time on one interface/instance - this is exactly how P2P is
    # designed to coexist with STA mode. A reconciliation loop (rather than
    # a one-shot) is used because miracle-wifid regenerates and restarts
    # its wpa_supplicant (fresh, without our injected network) whenever the
    # link is (re)established, e.g. after a crash/interface replug.
    systemd.services.miraclecast-join-wifi = {
      description = "Join normal Wi-Fi network on the interface shared with Miracast";
      after = [ "miraclecast-wifid.service" ];
      wants = [ "miraclecast-wifid.service" ];
      wantedBy = [ "multi-user.target" ];
      path = [ pkgs.wpa_supplicant ];
      serviceConfig = {
        ExecStart = pkgs.writeShellScript "miraclecast-join-wifi" ''
          set -eu
          ctrl="/run/miracle/wifi/${cfg.interface}"
          psk_file="${lib.optionalString (global.secretFile != null) config.sops.secrets.${pskSecretName}.path}"

          wpa_cli_() { wpa_cli -p /run/miracle/wifi -i "${cfg.interface}" "$@"; }

          while true; do
            if [ -S "$ctrl" ] && ! wpa_cli_ list_networks 2>/dev/null | grep -q "^0"; then
              psk="$(cat "$psk_file")"
              id=$(wpa_cli_ add_network | tail -n1)
              wpa_cli_ set_network "$id" ssid "\"${cfg.network.ssid}\""
              wpa_cli_ set_network "$id" psk "\"$psk\""
              wpa_cli_ enable_network "$id"
            fi
            sleep 5
          done
        '';
        Restart = "always";
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
