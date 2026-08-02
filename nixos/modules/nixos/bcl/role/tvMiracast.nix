{ config, lib, pkgs, ... }:
let
  cfg = config.bcl.role.tv.miracast;
  global = config.bcl.global;

  # SSID(s) to inject into miracle-wifid's own wpa_supplicant instance for
  # normal (STA) networking, alongside its P2P/Miracast role.
  #
  # If cfg.network.ssid is set explicitly, only that one SSID is used.
  # Otherwise, self-deduce candidates from the infra's already-known wifi
  # networks - the exact same source bcl.wifi.nix's NetworkManager
  # profiles are generated from: any SSID with a
  # "networking.wireless.<ssid>.password" key in bcl.global.secretFile,
  # plus any key of bcl.global.networking.wireless. All candidates get
  # injected as SEPARATE wpa_supplicant networks below (like a normal
  # multi-profile wpa_supplicant/NetworkManager config) - wpa_supplicant
  # itself then picks whichever network is actually in range (by signal
  # strength), so this role doesn't need its own dedicated SSID
  # hardcoded, it can share the same "known networks" list every other
  # host on the infra already uses.
  ssidsFromSecretFile =
    if global.secretFile == null then []
    else
      let
        lines = lib.splitString "\n" (builtins.readFile global.secretFile);
        prefix = "networking.wireless.";
        extractSsid = line:
          if lib.hasPrefix prefix line
          then
            let
              withoutPrefix = lib.removePrefix prefix line;
              parts = lib.splitString "." withoutPrefix;
            in
              # parts = [ "<ssid>" "password:" ... ] — need at least 2
              # elements and the second element must start with "password:"
              if lib.length parts >= 2 && lib.hasPrefix "password:" (lib.elemAt parts 1)
              then lib.head parts
              else null
          else null;
      in lib.filter (s: s != null) (map extractSsid lines);

  ssidsToJoin =
    if cfg.network.ssid != null then [ cfg.network.ssid ]
    else lib.unique (ssidsFromSecretFile ++ builtins.attrNames global.networking.wireless);

  pskSecretNameFor = ssid: "networking.wireless.${ssid}.password";

  # Detects the (assumed single) wireless network interface at runtime, by
  # looking for the first /sys/class/net/*/wireless dir - avoids requiring
  # the interface name as a static option, since it can vary across
  # hardware/driver/udev naming.
  detectWifiInterface = pkgs.writeShellScript "miraclecast-detect-interface" ''
    set -eu
    for w in /sys/class/net/*/wireless; do
      [ -d "$w" ] || continue
      name=$(basename "$(dirname "$w")")
      # Skip miracle-wifid's own P2P group interfaces (named
      # "p2p-<iface>-N" thanks to --use-dev). These only exist while a
      # cast is actively connected, also have a "wireless" sysfs dir, and
      # sort ALPHABETICALLY BEFORE the real physical interface ("p" <
      # "w"/etc) - without this filter, this function would start
      # returning the transient P2P group interface instead of the
      # physical STA interface the moment a phone connects, breaking
      # every caller that assumes it always gets the STA interface (SSID
      # injection, channel-forcing, device_name - see
      # miraclecast-join-wifi below). Confirmed live: right after a
      # successful P2P-GO-NEG-SUCCESS, this returned "p2p-wlo1-0" instead
      # of "wlo1", and miraclecast-join-wifi's next loop iteration then
      # ran wpa_cli against that transient interface and crashed
      # (set -eu, unguarded wpa_cli_ call), which combined with
      # Restart=always/RestartSec=2s crash-looped the service for the
      # remainder of the cast and killed it.
      case "$name" in
        p2p-*) continue ;;
      esac
      printf '%s' "$name"
      exit 0
    done
    echo "miraclecast: no wireless interface found" >&2
    exit 1
  '';

  # miracle-gst (res/miracle-gst in upstream) is a plain bash script that
  # builds and execs a hardcoded gst-launch-1.0 pipeline string - it does
  # NOT expose udpsrc's buffer-size or rtpjitterbuffer's latency as CLI
  # options. Confirmed live via `nstat -az | grep Udp`: UdpRcvbufErrors
  # was non-zero (310 seen in one session) - real packet loss happening at
  # the KERNEL UDP socket layer because udpsrc's receive buffer (its
  # default `buffer-size` GstUDPSrc property, backed by SO_RCVBUF) fills
  # up faster than the pipeline drains it during brief scheduling
  # hiccups - visible on-screen as intermittent macroblock
  # artifacts/glitches, since lost RTP packets in an MPEG-TS/H.264 stream
  # corrupt whatever frame(s) they belonged to (no retransmission in this
  # WFD RTP stream). Also bumping rtpjitterbuffer's latency from its
  # hardcoded 100ms so brief network jitter/reordering over the P2P Wi-Fi
  # link doesn't itself look like loss to the jitterbuffer. Patching just
  # these two numeric values in the vendored script (at the same
  # postPatch step nixpkgs already uses to fix up the gst-launch-1.0
  # path) is deliberately narrow in scope - it only affects RTP-receive
  # buffering, not any decode/render element, unlike the GPU-decode
  # (vaapih264dec) experiment tried earlier that broke video AND audio
  # entirely and was reverted.
  #
  # NOTE: an attempt was made here to also replace "autovideosink" with
  # an explicit "waylandsink fullscreen=true" (to fix the cast window
  # rendering as a small native-resolution window instead of fullscreen)
  # - REVERTED. Standalone/explicit waylandsink in this gst-plugins-bad
  # version fails immediately with "Window has no size set" /
  # "gst_wl_window_ensure_fullscreen: assertion 'self' failed" as soon as
  # the first real frame arrives (confirmed live via
  # `journalctl -u miraclecast-sinkctl`), which is fatal to the WHOLE
  # gst-launch-1.0 process - since video and audio are two branches of
  # the SAME pipeline/process here, this took down audio too, not just
  # video (total cast failure, confirmed by user: "no video, no sound").
  # autovideosink's own internal wrapping of waylandsink does NOT hit
  # this - it must set up the window/size-negotiation differently
  # (likely via its own GstVideoOverlay handling before the real sink is
  # swapped in) - so autovideosink is kept here for now. The fullscreen
  # sizing problem needs a different fix (e.g. a sway `for_window` rule
  # matching GstWaylandSink's actual Wayland app_id/title once
  # identified, rather than an element property), to be investigated
  # separately without repeating this outage.
  #
  # Further latency bump (250ms -> 400ms): after the buffer-size fix
  # above, `nstat -az | grep Udp` confirmed UdpRcvbufErrors dropped to 0
  # (no more kernel-level overflow), yet some visible artifacts
  # persisted. `iw dev <p2p-iface> station dump` on the connected peer
  # showed only -65/-68 dBm signal on a 2.4GHz P2P group (channel 6,
  # negotiated automatically by wpa_supplicant/the phone - miracle-wifid
  # doesn't expose any option to force 5GHz or a specific channel, and
  # patching that in would mean changing miraclecast's C source, not just
  # this script - too risky to attempt blindly after two pipeline changes
  # already caused full outages this session). That signal/channel
  # combination is consistent with genuine RF-level frame loss (real
  # radio interference/retries on a busy 2.4GHz band), which no amount of
  # RECEIVE-side buffering can fully recover since the data was never
  # correctly received in the first place - only the reordering/jitter
  # portion of it is something rtpjitterbuffer can help smooth over. This
  # extra latency is a modest, low-risk trade-off (turns brief
  # reordering into "late but complete" instead of "gap", at the cost of
  # ~150ms more end-to-end lag) - it will NOT eliminate artifacts caused
  # by frames that were truly never received; that would require
  # improving the actual Wi-Fi signal (e.g. reducing distance/obstacles
  # between the TV and the phone, or reducing 2.4GHz interference from
  # other devices).
  miraclecastTuned = pkgs.miraclecast.overrideAttrs (oldAttrs: {
    postPatch = (oldAttrs.postPatch or "") + ''
      substituteInPlace res/miracle-gst \
        --replace-fail 'rtpjitterbuffer latency=100' 'rtpjitterbuffer latency=400' \
        --replace-fail 'udpsrc port=$PORT caps=' 'udpsrc port=$PORT buffer-size=2097152 caps='
    '';
  });

  # miracle-sinkctl (running as root) spawns `miracle-gst` (via a bare-name
  # execvpe lookup on PATH) to actually render the incoming video/audio.
  # `miracle-gst`'s GStreamer pipeline refuses to work correctly as root
  # though: it logs "XDG_RUNTIME_DIR (/run/user/<uid>) is not owned by us
  # (uid 0), but by uid <uid>!" and never actually renders anything to the
  # screen, even though the RTSP session and pipeline otherwise reach
  # PLAYING state with caps correctly negotiated (confirmed via real IP
  # traffic on the RTSP/RTP ports and `gst-launch-1.0 -v` output, but no
  # video ever appears on the TV). This shim intercepts the `miracle-gst`
  # lookup (placed first in the sinkctl service's PATH, ahead of
  # miraclecast's own bin dir) and re-execs it as the `tv` user via
  # `runuser`, inheriting the WAYLAND_DISPLAY/XDG_RUNTIME_DIR exported by
  # the sinkctl service's ExecStart below.
  #
  # GST_PLUGIN_FEATURE_RANK=kmssink:0 is also required: `autovideosink`
  # picks elements purely by GStreamer rank, and kmssink's rank
  # (secondary, 128) is HIGHER than waylandsink's (marginal, 64) in this
  # nixpkgs build - so autovideosink tries kmssink FIRST. kmssink's
  # opening of /dev/dri/cardN during the initial READY/PAUSED autoplug
  # probe succeeds (logind grants the tv user's active session read/write
  # access to the DRM device), so autovideosink "picks" it and never even
  # tries waylandsink - but kmssink can NEVER actually render frames here,
  # because sway (also running as the tv user, on the same seat) already
  # holds DRM master for that device, and only a single DRM master may
  # perform modesetting/plane operations at a time. This only surfaces
  # once real frames arrive ("drmModeSetPlane failed: Permission denied
  # (13)"), well after the pipeline reports PLAYING - confirmed live by
  # reproducing the exact same nondeterministic kmssink-vs-waylandsink
  # autoplug choice with a synthetic `videotestsrc ! autovideosink` test
  # pipeline, and confirming `GST_PLUGIN_FEATURE_RANK=kmssink:0` reliably
  # forces the working GL/Wayland sink instead.
  miracleGstShim = pkgs.writeShellScriptBin "miracle-gst" ''
    export GST_PLUGIN_FEATURE_RANK=kmssink:0
    exec ${pkgs.util-linux}/bin/runuser -u tv -- ${miraclecastTuned}/bin/miracle-gst "$@"
  '';
in
{
  options.bcl.role.tv.miracast = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
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
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = ''
          SSID of the Wi-Fi network the auto-detected wireless interface
          should associate to for normal networking (e.g. to reach
          Jellyfin), concurrently with acting as a Miracast receiver.

          Defaults to null, which self-deduces candidate SSIDs from the
          infra's already-known wifi networks instead of requiring one to
          be hardcoded here: every SSID with a
          "networking.wireless.<ssid>.password" key in
          bcl.global.secretFile, plus every key of
          bcl.global.networking.wireless, is injected as a separate
          wpa_supplicant network (same as a normal multi-profile
          wpa_supplicant/NetworkManager config) - wpa_supplicant itself
          then picks whichever network is actually in range (by signal
          strength), so this TV role doesn't need its own dedicated SSID
          configured, it can share the same "known networks" list every
          other host on the infra already uses (via bcl.wifi.nix).

          Set explicitly only if this TV should join one specific SSID
          regardless of what else is known/in range.
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

    # Allow the P2P group-owner's DHCP server (miracle-dhcp, spawned by
    # miracle-wifid) to receive DHCP DISCOVER/REQUEST broadcasts from
    # casting devices on the dynamically-created P2P group interface
    # (always named "p2p-<parent-iface>-<N>", e.g. p2p-wlo1-0 - the "p2p-+"
    # key below uses iptables' trailing "+" wildcard to match any such
    # name). Without this, the NixOS firewall's default-deny policy
    # silently drops the incoming DHCP packets (new/non-established
    # connections are dropped unless explicitly allowed): the phone
    # completes the WPA/P2P handshake fine (visible as "AP-STA-CONNECTED"
    # in miracle-wifid's log) but then never gets an IP, so Android shows
    # "connecting..." for a while and then gives up, removing the device
    # from its cast list - confirmed via `iptables -L nixos-fw -v` showing
    # only ssh/icmp/established allowed, everything else hitting
    # nixos-fw-log-refuse, and via `ip addr`/miracle-dhcp both being up and
    # correctly configured on the group interface.
    #
    # Port 7236 (the standard Wi-Fi Display RTP port, hardcoded by
    # miraclecast) needs the same treatment: the RTSP control session is a
    # TCP connection sinkctl makes OUT to the phone (unaffected by the
    # default-deny INBOUND policy), so it completes fine and `miracle-gst`'s
    # GStreamer pipeline reaches PLAYING with correct caps negotiated - but
    # the phone's actual inbound RTP video/audio packets on UDP 7236 were
    # silently dropped, so no video ever reached the TV despite every other
    # part of the pipeline reporting success.
    networking.firewall.interfaces."p2p-+".allowedUDPPorts = [ 67 7236 ];

    sops.secrets = lib.mkIf (global.secretFile != null) (
      lib.listToAttrs (map (ssid: {
        name = pskSecretNameFor ssid;
        value = { sopsFile = global.secretFile; };
      }) ssidsToJoin)
    );

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
          # --use-dev works around an upstream issue where AP-STA-CONNECTED
          # events delivered via the bus_dev (p2p-dev-<iface>) control
          # socket arrive without an "ifname" field, causing
          # supplicant_event_ap_sta_connected() to bail out early and never
          # bind the connecting peer to its P2P group. Without this flag,
          # `Connected` on the sink link never flips true and
          # miracle-sinkctl never attempts the RTSP handshake - Android
          # shows "connecting..." for ~30s then gives up. Confirmed via
          # `miracle-wifid --log-level debug` showing "no ifname in
          # AP-STA-CONNECTED" without the flag, and "bind peer ... to
          # existing local group" with it.
          exec ${pkgs.miraclecast}/bin/miracle-wifid --interface="$iface" --use-dev
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
      path = [ pkgs.wpa_supplicant pkgs.iw pkgs.gawk ];
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

          while true; do
            iface=$(${detectWifiInterface} 2>/dev/null) || { sleep 5; continue; }
            ctrl="/run/miracle/wifi/$iface"

            wpa_cli_() { wpa_cli -p /run/miracle/wifi -i "$iface" "$@"; }

            # Guard every wpa_cli_ call here with `|| true` (alongside the
            # `set -eu` at the top of this script): a transient failure
            # (e.g. miracle-wifid mid-(re)initializing its wpa_supplicant
            # instance, or the wpa_cli client-side ctrl-socket dir
            # momentarily missing/being recreated) would otherwise exit
            # the WHOLE script immediately, and combined with
            # Restart=always/RestartSec=2s that crash-loops this service
            # instead of just skipping to the next 5s reconciliation pass
            # - confirmed live to happen right as a phone's P2P group was
            # forming, killing the in-progress cast.
            # Inject every candidate SSID (see ssidsToJoin above) as its
            # own wpa_supplicant network, skipping ones already present -
            # letting wpa_supplicant pick whichever is actually in range
            # itself, exactly like a normal multi-profile wpa_supplicant/
            # NetworkManager config would. Candidates are baked in at
            # build time as tab-separated "ssid<TAB>psk-secret-path"
            # lines, since the SSID list and per-SSID sops secret paths
            # are only known at Nix eval time, not at runtime.
            #
            # Deliberately avoids `cut`/external text-processing tools
            # beyond what's already used elsewhere in this script (plain
            # `read`/`grep`/`printf`) to sidestep any doubt about which
            # coreutils are actually on PATH for this service.
            if [ -S "$ctrl" ]; then
              existing_ssids=""
              while IFS=$'\t' read -r ex_id ex_ssid ex_rest; do
                [ -z "$ex_id" ] && continue
                existing_ssids="$existing_ssids
$ex_ssid"
              done < <(wpa_cli_ list_networks 2>/dev/null | tail -n +2)
              while IFS=$'\t' read -r cand_ssid cand_psk_file; do
                [ -z "$cand_ssid" ] && continue
                if printf '%s\n' "$existing_ssids" | grep -qxF "$cand_ssid"; then
                  continue
                fi
                psk="$(cat "$cand_psk_file" 2>/dev/null)"
                if [ -z "$psk" ]; then
                  echo "miraclecast-join-wifi: could not read psk file for SSID '$cand_ssid' ($cand_psk_file), skipping" >&2
                  continue
                fi
                add_out="$(wpa_cli_ add_network 2>&1)"
                id="$(printf '%s\n' "$add_out" | tail -n1)"
                case "$id" in
                  ""|*[!0-9]*)
                    echo "miraclecast-join-wifi: add_network failed for SSID '$cand_ssid' on $iface: $add_out" >&2
                    id=""
                    ;;
                esac
                if [ -n "$id" ]; then
                  set_ssid_out="$(wpa_cli_ set_network "$id" ssid "\"$cand_ssid\"" 2>&1)" || true
                  set_psk_out="$(wpa_cli_ set_network "$id" psk "\"$psk\"" 2>&1)" || true
                  enable_out="$(wpa_cli_ enable_network "$id" 2>&1)" || true
                  echo "miraclecast-join-wifi: added network '$cand_ssid' (id=$id) on $iface (set_ssid=$set_ssid_out set_psk=$set_psk_out enable=$enable_out)" >&2
                fi
              done <<'MIRACAST_SSID_CANDIDATES'
${if global.secretFile != null then lib.concatMapStringsSep "\n" (ssid: "${ssid}\t${config.sops.secrets.${pskSecretNameFor ssid}.path}") ssidsToJoin else ""}
MIRACAST_SSID_CANDIDATES
            fi

            # Force the P2P group onto the SAME channel/band as the
            # normal STA connection above, instead of leaving channel
            # selection to wpa_supplicant/the phone's own negotiation
            # (which picked a 2.4GHz channel here - confirmed live via
            # `iw dev p2p-<iface>-N info` showing "channel 6 (2437 MHz)"
            # while the STA link (`iw dev <iface> info`) was on "channel
            # 36 (5180 MHz)"). Two consequences of that mismatch,
            # confirmed by both being on the SAME physical radio
            # (`wiphy 0` for both interfaces): (1) 2.4GHz is a much more
            # congested/interference-prone band than 5GHz for weak-signal
            # loss: `iw dev <p2p-iface> station dump` showed only
            # -65/-68 dBm for the connected phone; (2) with STA and P2P
            # simultaneously on two DIFFERENT channels on one physical
            # radio, the driver/firmware must time-slice between them
            # (multi-channel concurrency/MCC) rather than truly
            # transmitting on both at once - itself a further source of
            # periodic loss on both links, independent of RF quality.
            # Setting the SAME channel for both lets the radio use
            # single-channel concurrency (SCC) instead, avoiding that
            # time-slicing entirely. p2p_oper_channel/p2p_oper_reg_class
            # are wpa_supplicant GLOBAL params (confirmed settable live
            # via `wpa_cli set p2p_oper_channel/p2p_oper_reg_class` ->
            # "OK") that only influence the NEXT P2P group formation, not
            # any already-established group - reading the STA's current
            # channel fresh every loop iteration (rather than hardcoding
            # it) keeps this correct if the AP ever renegotiates to a
            # different channel. Global operating class mapping is only
            # implemented for the common 20MHz-channel 5GHz classes here
            # (115: UNII-1 36/40/44/48, 124: UNII-3 149/153/157/161) -
            # if the STA is on 2.4GHz or some other 5GHz channel/width,
            # this intentionally does nothing and P2P keeps its own
            # default channel selection.
            #
            # EXPERIMENTAL: forcing this may or may not actually be
            # honored by the phone's own P2P/GO-negotiation stack
            # (channel selection during GO Negotiation is a
            # two-way/proposed-and-confirmed process, not something one
            # side can unilaterally dictate) - not a confirmed/stable
            # recipe, worth verifying live via `iw dev <p2p-iface> info`
            # after reconnecting a cast.
            sta_channel=$(iw dev "$iface" info 2>/dev/null | awk '/channel/ {print $2}')
            reg_class=""
            case "$sta_channel" in
              36|40|44|48) reg_class=115 ;;
              149|153|157|161) reg_class=124 ;;
            esac
            if [ -S "$ctrl" ] && [ -n "$reg_class" ]; then
              wpa_cli_ set p2p_oper_channel "$sta_channel" >/dev/null 2>&1 || true
              wpa_cli_ set p2p_oper_reg_class "$reg_class" >/dev/null 2>&1 || true
            fi

            # Advertise the host's hostname as the cast device's friendly
            # name directly to wpa_supplicant's "device_name" global
            # param, INSTEAD of relying solely on
            # miraclecast-set-friendly-name.service's D-Bus
            # `FriendlyName` Property.Set call. That service alone is
            # racy: wifid's own link_set_friendly_name() (wifid-link.c)
            # only forwards the new name to wpa_supplicant
            # (supplicant_set_friendly_name -> "SET device_name ...") if
            # supplicant_is_ready(l->s) is true AT THE EXACT MOMENT the
            # property is set - otherwise it's silently stored in
            # wifid's own memory only (so `busctl get-property
            # FriendlyName` keeps reporting the correct hostname
            # forever), while wpa_supplicant's actual device_name is
            # simply never updated and keeps showing wpa_supplicant's own
            # built-in default. Confirmed live: `busctl get-property
            # FriendlyName` returned "salon-0" while
            # `wpa_cli get device_name` simultaneously returned "unknown"
            # (the phone was displaying "unknown" as the cast name).
            # Setting device_name directly here bypasses that race
            # entirely, and re-asserting it every loop iteration
            # self-heals if miracle-wifid ever regenerates its
            # wpa_supplicant instance (same reasoning as the SSID/PSK
            # injection above).
            if [ -S "$ctrl" ]; then
              wpa_cli_ set device_name "${config.networking.hostName}" >/dev/null 2>&1 || true
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
      # miracleGstShim MUST come before pkgs.miraclecast here: sinkctl looks
      # up "miracle-gst" by bare name (execvpe on PATH), and the first match
      # wins - see miracleGstShim's own comment above for why it needs to
      # intercept that lookup.
      path = [ miracleGstShim pkgs.miraclecast ];
      serviceConfig = {
        ExecStart = pkgs.writeShellScript "miraclecast-sinkctl-start" ''
          set -eu
          runtime_dir="/run/user/$(${pkgs.coreutils}/bin/id -u tv)"

          # Wait for the tv user's Wayland compositor (sway) to be up, so
          # miracle-gst has somewhere to render the incoming video into.
          #
          # NOTE: a previous version of this wait loop used
          # `until lock=$(ls "$runtime_dir"/wayland-*.lock | head -n1); do
          # sleep 1; done` - which is BROKEN: the exit status of a
          # `var=$(pipeline)` assignment is the exit status of the LAST
          # command in the pipeline, i.e. `head -n1`, which always
          # succeeds (exit 0) even when it reads zero bytes because `ls`
          # found no matching file. So that loop never actually waited -
          # it always fell through on its very first iteration, with
          # `lock` empty whenever sway's socket didn't exist yet. Since
          # this service is long-running and only computes
          # WAYLAND_DISPLAY once at its own startup, hitting that race at
          # boot (sinkctl starting before sway creates its
          # wayland-*.lock) permanently cached WAYLAND_DISPLAY="" for the
          # service's whole lifetime - confirmed live via
          # `cat /proc/<sinkctl-pid>/environ`showing an empty
          # WAYLAND_DISPLAY after a cold reboot, even though a valid
          # wayland-1 socket existed by the time a phone actually
          # connected. Symptom: audio plays fine (routed via PulseAudio,
          # unaffected) but no video ever appears, because every
          # Wayland-based GStreamer video sink fails to connect and
          # autovideosink silently falls back to its internal no-op
          # fake-video-sink. This plain bash glob (no ls/head pipe)
          # doesn't have that problem: the loop condition is a direct
          # `[ -e ... ]` test, not a pipeline's exit status.
          lock=""
          until [ -n "$lock" ]; do
            for candidate in "$runtime_dir"/wayland-*.lock; do
              [ -e "$candidate" ] && lock="$candidate" && break
            done
            [ -n "$lock" ] || sleep 1
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

    # `miracle-sinkctl run <iface>` only enables P2P discovery
    # (P2PScanning=true) ONCE, at startup (see run_on() in sinkctl.c). Per
    # upstream's own code, wpa_supplicant's P2P_FIND naturally stops after
    # ~20-30s (confirmed live via `busctl get-property ... P2PScanning`
    # polling every 10s: it flips back to false and NEVER recovers on its
    # own) and nothing in miraclecast re-issues it unless a peer
    # connection attempt is already in flight (formation-failure/
    # disconnect handlers) - there is NO generic idle keepalive. Result:
    # the TV becomes invisible to phones a few seconds after boot, even
    # though every service reports healthy. `miracle-wifictl p2p-scan` is
    # the obvious fix but its command is marked CLI-only (CLI_Y) in
    # wifictl.c, so it refuses non-interactive one-shot invocation
    # ("unknown operation p2p-scan") - falling back to a direct D-Bus
    # Property.Set call on P2PScanning instead (confirmed working live).
    # The link's D-Bus object path is escaped-hex-encoded from its label
    # (e.g. ifindex "3" -> "_33", since '3' is ASCII 0x33) which isn't
    # worth reimplementing in shell - just discover the (always single,
    # per this module's single-interface design) link path dynamically
    # via `busctl tree` each run instead.
    systemd.services.miraclecast-p2p-keepalive = {
      description = "Keep MiracleCast P2P discovery (re-)enabled";
      after = [ "miraclecast-wifid.service" ];
      wants = [ "miraclecast-wifid.service" ];
      serviceConfig.Type = "oneshot";
      serviceConfig.ExecStart = pkgs.writeShellScript "miraclecast-p2p-keepalive" ''
        set -eu
        link_path=$(${pkgs.systemd}/bin/busctl tree org.freedesktop.miracle.wifi 2>/dev/null \
          | ${pkgs.gnugrep}/bin/grep -o '/org/freedesktop/miracle/wifi/link/_[0-9A-Za-z]*' \
          | head -n1)
        if [ -z "$link_path" ]; then
          exit 0
        fi

        # Only re-arm scanning if it's CURRENTLY disabled. Blindly calling
        # Set every 15s regardless of state re-triggers wpa_supplicant's
        # P2P_FIND even while a scan or GO-negotiation is already
        # in-flight, logged as "P2P: Reject scan trigger since one is
        # already pending" - confirmed live to coincide exactly with a
        # phone's P2P-PROV-DISC-PBC-REQ retries never reaching
        # AP-STA-CONNECTED (a full regression back to the "connection
        # fails after ~30s" symptom this timer was meant to fix in the
        # first place). Checking current state first avoids interrupting
        # an in-progress connection attempt.
        scanning=$(${pkgs.systemd}/bin/busctl get-property org.freedesktop.miracle.wifi \
          "$link_path" org.freedesktop.miracle.wifi.Link P2PScanning 2>/dev/null \
          | ${pkgs.gawk}/bin/awk '{print $2}')
        if [ "$scanning" != "true" ]; then
          # `|| true`: wifid can still be finishing its own internal P2P
          # setup for a brief moment right after it starts (confirmed
          # live: "ERROR: supplicant: invalid arguments
          # (supplicant_p2p_start_scan())" logged once at boot, exactly
          # when this timer's OnBootSec=5s fired essentially concurrently
          # with miraclecast-wifid.service's own startup) - this is a
          # harmless, self-healing race (the next run 15s later always
          # succeeds), not worth hard-failing the oneshot unit over.
          ${pkgs.systemd}/bin/busctl set-property org.freedesktop.miracle.wifi \
            "$link_path" org.freedesktop.miracle.wifi.Link P2PScanning b true || true
        fi
      '';
    };

    systemd.timers.miraclecast-p2p-keepalive = {
      description = "Timer for miraclecast-p2p-keepalive";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "5s";
        OnUnitActiveSec = "15s";
      };
    };

    # Upstream miracle-wifid is *supposed* to auto-derive the cast device's
    # advertised name from the system's hostname (see manager_read_name()
    # in wifid.c, which queries org.freedesktop.hostname1's "Hostname"
    # property over D-Bus at startup) - but confirmed live via
    # `busctl get-property ... FriendlyName` that it stays permanently
    # empty here even though `hostnamectl` correctly reports the static
    # hostname, so the phone falls back to displaying the hardcoded
    # "Miracle" default (device_name sent to wpa_supplicant when
    # l->friendly_name is unset - see supplicant_started() in
    # wifid-supplicant.c). Rather than chase down why that upstream
    # hostname1 lookup silently fails/never applies (skipped for now -
    # not worth the investigation for a cosmetic feature), just set it
    # ourselves directly via the same Property.Set mechanism already used
    # for the P2P-keepalive workaround above, using the hostname NixOS
    # itself is configured with (known at build time, so no runtime
    # hostname1 round-trip needed at all).
    systemd.services.miraclecast-set-friendly-name = {
      description = "Set MiracleCast Wi-Fi Display friendly name to the host's hostname";
      after = [ "miraclecast-wifid.service" ];
      wants = [ "miraclecast-wifid.service" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = pkgs.writeShellScript "miraclecast-set-friendly-name" ''
          set -eu
          link_path=""
          for i in $(seq 1 30); do
            link_path=$(${pkgs.systemd}/bin/busctl tree org.freedesktop.miracle.wifi 2>/dev/null \
              | ${pkgs.gnugrep}/bin/grep -o '/org/freedesktop/miracle/wifi/link/_[0-9A-Za-z]*' \
              | head -n1)
            [ -n "$link_path" ] && break
            sleep 1
          done
          if [ -z "$link_path" ]; then
            echo "miraclecast-set-friendly-name: no link found after 30s, giving up" >&2
            exit 1
          fi
          ${pkgs.systemd}/bin/busctl set-property org.freedesktop.miracle.wifi \
            "$link_path" org.freedesktop.miracle.wifi.Link FriendlyName s "${config.networking.hostName}"
        '';
        Restart = "on-failure";
        RestartSec = "5s";
      };
    };
  };
}
