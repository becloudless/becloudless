{ config, lib, pkgs, ... }:
let
  cfg = config.bcl.role.tv.miracast;
  global = config.bcl.global;
  pskSecretName = "networking.wireless.${cfg.network.ssid}.password";

  # Detects the (assumed single) wireless network interface at runtime, by
  # looking for the first /sys/class/net/*/wireless dir - avoids requiring
  # the interface name as a static option, since it can vary across
  # hardware/driver/udev naming.
  detectWifiInterface = pkgs.writeShellScript "miraclecast-detect-interface" ''
    set -eu
    for w in /sys/class/net/*/wireless; do
      [ -d "$w" ] || continue
      basename "$(dirname "$w")"
      exit 0
    done
    echo "miraclecast: no wireless interface found" >&2
    exit 1
  '';
in
{
  options.bcl.role.tv.miracast = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Whether to enable the Miracast (Wi-Fi Display) receiver, to cast
        from Android devices without Google/Chromecast.

        EXPERIMENTAL / UNVERIFIED: this runs concurrently with normal Wi-Fi
        networking on the SAME physical radio (the auto-detected wireless
        interface), the same idea Android itself uses to keep a phone's own
        Wi-Fi connected while it
        casts (P2P group formation happens via a separate virtual interface
        - e.g. `p2p-dev-wlan0` - alongside the normal STA association,
        rather than needing a second radio). However, upstream MiracleCast
        has an explicitly still-open issue about this exact scenario
        (https://github.com/albfan/miraclecast/issues/75, filed 2016, no
        clean fix as of the maintainer's own last comment in Sep 2025) -
        there is no officially confirmed/stable recipe for it, only
        best-effort workarounds from various users. What's implemented
        here is one such best-effort approach (injecting a station network
        into miracle-wifid's own wpa_supplicant instance via its control
        socket, see `miraclecast-join-wifi` below) that is NOT validated by
        upstream and may break across driver/kernel/miraclecast updates.
        Test thoroughly before relying on it; if it proves unreliable, the
        safe fallback is a dedicated second wifi adapter for Miracast,
        leaving the primary adapter solely under NetworkManager.

        Confirm your hardware/driver at least supports STA+P2P
        concurrency in principle via `iw phy <phy> info`: look for a
        "valid interface combinations" entry listing "managed" together
        with "P2P-client, P2P-GO" allowing more than 1 total interface
        (checked on an Intel AX201: supported) - this is necessary but not
        sufficient, since the fragility above is in miraclecast's process
        orchestration, not the underlying radio capability.
      '';
    };
    network = {
      ssid = lib.mkOption {
        type = lib.types.str;
        description = ''
          SSID of the Wi-Fi network the auto-detected wireless interface
          should associate to for normal networking (e.g. to reach
          Jellyfin), concurrently with acting as a Miracast receiver.
        '';
      };
    };
  };

  config = lib.mkIf (config.bcl.role.name == "tv" && cfg.enable) {
    # miracle-wifid needs to be the sole owner of the wireless interface's
    # wpa_supplicant (it always spawns/manages its own instance), so
    # NetworkManager must not also try to manage/associate any wifi device.
    # Assumes a single wireless adapter is present (self-detected at
    # runtime elsewhere below); if several are present, all of them become
    # unmanaged by NetworkManager here even though only the auto-detected
    # one is actually driven by miracle-wifid/the join-wifi service.
    networking.networkmanager.unmanaged = [ "type:wifi" ];

    # DHCP client for the STA role on the wireless interface, scoped via a
    # glob rather than a static name since it's auto-detected at runtime.
    # Predictable wireless interface names always start with "wl" (wlan*,
    # wlp*, wlo*, wlx*) under systemd's naming scheme, so this doesn't
    # interfere with NetworkManager handling everything else (e.g. Ethernet).
    #
    # `networking.useDHCP` must be forced back on here: the NetworkManager
    # module unconditionally sets it to `false` whenever NetworkManager is
    # enabled (see nixos/modules/services/networking/networkmanager.nix),
    # and dhcpcd's own systemd service is entirely disabled unless
    # `useDHCP` is true (or an interface explicitly sets `useDHCP = true`).
    # Without this override, `allowInterfaces` below has no effect at all
    # because the dhcpcd service never starts in the first place - leaving
    # the wifi interface with no DHCP client whatsoever once it's unmanaged
    # from NetworkManager (total loss of network on that radio).
    networking.useDHCP = lib.mkForce true;
    networking.dhcpcd.allowInterfaces = [ "wl*" ];

    sops.secrets.${pskSecretName} = lib.mkIf (global.secretFile != null) {
      sopsFile = global.secretFile;
    };

    # Tag every wireless interface with "miracle", so miracle-wifid (built
    # with rely-udev=true) is able to manage it. Since miracle-wifid is
    # started below with an explicit --interface=<auto-detected>, only that
    # one interface is actually used even if several are tagged.
    services.udev.extraRules = ''
      SUBSYSTEM=="net", ACTION=="add|change", TEST=="wireless", TAG+="miracle"
    '';

    # dbus policy allowing org.freedesktop.miracle.wifi (bundled in the package).
    services.dbus.packages = [ pkgs.miraclecast ];

    environment.systemPackages = [ pkgs.miraclecast ];

    # Wi-Fi Direct connections are auto-accepted with no PIN/confirmation
    # (built-in miraclecast behaviour) - any nearby device can cast to this
    # TV once `miracle-sinkctl run <link>` is running (see
    # miraclecast-sinkctl below).

    systemd.services.miraclecast-wifid = {
      description = "MiracleCast Wi-Fi Display (P2P) management daemon";
      after = [ "dbus.service" ];
      wants = [ "dbus.service" ];
      wantedBy = [ "multi-user.target" ];
      path = [ pkgs.wpa_supplicant pkgs.miraclecast ];
      serviceConfig = {
        ExecStart = pkgs.writeShellScript "miraclecast-wifid-start" ''
          set -eu
          iface=$(${detectWifiInterface})
          exec ${pkgs.miraclecast}/bin/miracle-wifid --interface="$iface"
        '';
        Restart = "on-failure";
        RestartSec = "2s";
      };
    };

    # Concurrently join the normal Wi-Fi network on the SAME (auto-detected)
    # interface, by talking to the wpa_supplicant instance that
    # miracle-wifid itself spawned (via its standard per-interface
    # ctrl_interface socket at /run/miracle/wifi/<interface>) rather than
    # running a second, conflicting wpa_supplicant.
    #
    # EXPERIMENTAL: this is a best-effort workaround, NOT a confirmed/
    # supported upstream recipe. See
    # https://github.com/albfan/miraclecast/issues/75 (open since 2016):
    # the only things upstream itself has ever confirmed working are (a)
    # `--lazy-managed` + toggling exclusive ownership between
    # NetworkManager and miracle-wifid (mutually exclusive, not
    # concurrent), and (b) the maintainer's own Sep-2025 finding that
    # stopping NetworkManager, starting miraclecast, then starting
    # NetworkManager again can leave two wpa_supplicant processes
    # coexisting (NetworkManager's on the main interface, miraclecast's on
    # the auto-created `p2p-dev-<iface>`) - itself described by the
    # maintainer as "not a big improvement" and unverified long-term.
    # A reconciliation loop (rather than a one-shot) is used here because
    # miracle-wifid regenerates and restarts its wpa_supplicant (fresh,
    # without our injected network) whenever the link is (re)established,
    # e.g. after a crash/interface replug.
    systemd.services.miraclecast-join-wifi = {
      description = "Join normal Wi-Fi network on the interface shared with Miracast";
      after = [ "miraclecast-wifid.service" ];
      wants = [ "miraclecast-wifid.service" ];
      wantedBy = [ "multi-user.target" ];
      path = [ pkgs.wpa_supplicant ];
      serviceConfig = {
        # NixOS patches wpa_cli to hard-code its OWN client-side ctrl
        # socket directory to /run/wpa_supplicant/client (regardless of
        # the `-p` server ctrl path passed on the command line - see
        # nixpkgs' wpa_supplicant unprivileged-daemon.patch). That
        # directory is normally only created by the system
        # wpa_supplicant.service's own ExecStartPre, and only when
        # `networking.wireless.userControlled.enable` is set - neither of
        # which applies here (we talk to miracle-wifid's OWN supplicant
        # instance, not the system one). Without it, every wpa_cli
        # invocation below fails immediately with "No such file or
        # directory", silently preventing the SSID/PSK from EVER being
        # injected - the root cause of a full loss of normal networking
        # observed in practice. Create it ourselves before use.
        ExecStartPre = "+${pkgs.coreutils}/bin/mkdir -p /run/wpa_supplicant/client";
        ExecStart = pkgs.writeShellScript "miraclecast-join-wifi" ''
          set -eu
          psk_file="${lib.optionalString (global.secretFile != null) config.sops.secrets.${pskSecretName}.path}"

          while true; do
            iface=$(${detectWifiInterface} 2>/dev/null) || { sleep 5; continue; }
            ctrl="/run/miracle/wifi/$iface"

            wpa_cli_() { wpa_cli -p /run/miracle/wifi -i "$iface" "$@"; }

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

          # miracle-wifid labels its dbus link objects by the interface's
          # ifindex (e.g. "3"), which is unknowable at build time and can
          # differ across hosts/reboots - so a static "run <link>" config
          # can't hardcode a link number. `miracle-sinkctl`'s link lookup
          # (ctl_wifi_search_link) also matches by INTERFACE NAME though,
          # so pass that instead. This previously relied on a static
          # /etc/miraclecastrc with `autocmd=run 1`, which silently never
          # matched any real link (labels are ifindex-based, not always
          # "1") - the sink was NEVER actually started, confirmed via
          # `busctl` showing the link's WfdSubelements/P2PScanning still
          # at their unset defaults despite the service running with no
          # errors.
          iface=$(${detectWifiInterface})
          exec ${pkgs.miraclecast}/bin/miracle-sinkctl run "$iface"
        '';
        Restart = "on-failure";
        RestartSec = "2s";
      };
    };
  };
}
