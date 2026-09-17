{ config, lib, ... }:
let
  cfg = config.bcl.role.serverVirt;
  bridgeCfg = cfg.iscsiDeviceBridge;

  # Every serverVirt container with a static macvlan IP is a candidate
  # owner. iSCSI sessions initiated from inside that container's network
  # namespace use this IP as their source address, which is how the host
  # (which sees the containers' /dev, /sys, and iSCSI kernel objects, but
  # not their private network namespaces) can tell which container a given
  # iSCSI-attached SCSI device belongs to.
  ipToContainer = lib.filterAttrs (ip: name: ip != null) (lib.mapAttrs'
    (name: c: lib.nameValuePair
      (if c.network != null then c.network.address else null)
      name)
    cfg.containers);

  ipToContainerCases = lib.concatStrings (lib.mapAttrsToList
    (ip: name: ''
      ${lib.strings.escapeShellArg ip}) printf '%s' ${lib.strings.escapeShellArg name}; return 0 ;;
    '')
    ipToContainer);

  script = ''
    #!/bin/sh
    # Grants a serverVirt container's docker cgroup access to a
    # newly-attached (or revokes access to a just-detached) host iSCSI
    # block device, so Longhorn (running inside the container, in a
    # private tmpfs /dev with no udev/mdev) can actually read/write the
    # device once it mknods its own /dev/longhorn/<volume> node for it.
    # See /memories/repo/longhorn-iscsi-device-discovery-container-nodes.md
    # for why no host-side mknod/nsenter step is needed.
    set -eu

    action="$1"      # add | remove
    instance="$2"    # "<kernel-device>-<major>-<minor>", e.g. "sdb-8-16"
    dev=$(printf '%s' "$instance" | sed -E 's/-[0-9]+-[0-9]+$//')
    major=$(printf '%s' "$instance" | sed -E 's/^.*-([0-9]+)-[0-9]+$/\1/')
    minor=$(printf '%s' "$instance" | sed -E 's/^.*-[0-9]+-([0-9]+)$/\1/')

    state_dir=/var/lib/bcl-iscsi-device-bridge
    mkdir -p "$state_dir"
    owner_file="$state_dir/owner-$dev"

    ip_to_container() {
      case "$1" in
        ${ipToContainerCases}
        *) return 1 ;;
      esac
    }

    # Only usable while the device (and its backing iSCSI session) is
    # still present, i.e. on "add". Walks:
    #   /sys/class/block/$dev/device -> .../hostN/...   (which scsi host)
    #   /sys/class/iscsi_session/sessionM/device -> .../hostN/...  (match)
    #   /sys/class/iscsi_connection/connectionM:0/local_ipaddr  (source IP)
    # ASSUMPTION (not yet live-verified): the running kernel exposes
    # `local_ipaddr` on iscsi_connection (ISCSI_PARAM_LOCAL_IPADDR). If it
    # doesn't exist on a given kernel, ownership cannot be determined and
    # the device is left without cgroup access (fails safe: Longhorn keeps
    # retrying/erroring rather than a device being granted to the wrong
    # container).
    find_owner_container() {
      hostpath=$(readlink -f "/sys/class/block/$dev/device" 2>/dev/null) || return 1
      hostnum=$(printf '%s\n' "$hostpath" | grep -oE '/host[0-9]+/' | head -1 | tr -d '/host')
      [ -n "$hostnum" ] || return 1

      for sess in /sys/class/iscsi_session/session*; do
        [ -e "$sess/device" ] || continue
        sesspath=$(readlink -f "$sess/device") || continue
        case "$sesspath" in
          */host"$hostnum"/*) : ;;
          *) continue ;;
        esac
        sessnum=$(basename "$sess" | sed 's/session//')
        connfile="/sys/class/iscsi_connection/connection$sessnum:0/local_ipaddr"
        [ -f "$connfile" ] || continue
        ip=$(cat "$connfile") || continue
        container=$(ip_to_container "$ip") || continue
        [ -n "$container" ] || continue
        printf '%s' "$container"
        return 0
      done
      return 1
    }

    # Re-applies the full set of currently-granted major:minor rules for a
    # container. NOTE (not yet live-verified): `docker update
    # --device-cgroup-rule` is assumed to REPLACE the container's whole
    # DeviceCgroupRules list with exactly what's passed in a given
    # invocation (not append across separate invocations) - hence tracking
    # the full desired set ourselves in $rule_file and always passing all
    # of it, every time, instead of trying to add/remove one rule at a
    # time.
    # KNOWN GAP: if $rule_file ends up empty (the container's last granted
    # device was just removed), we deliberately skip calling `docker
    # update` at all (it requires at least one --device-cgroup-rule to do
    # anything meaningful). That means the container's LAST previously
    # granted major:minor stays allowed at the docker/kernel level until
    # the container is restarted - acceptable for now (the device node
    # itself is gone, so there's nothing to read/write), but would matter
    # if that exact major:minor got reused by a different container's
    # volume before a restart happens.
    apply_rules_for_container() {
      container="$1"
      rule_file="$state_dir/rules-$container"
      touch "$rule_file"
      set -- 
      while read -r mm; do
        [ -n "$mm" ] && set -- "$@" --device-cgroup-rule="b $mm rwm"
      done < "$rule_file"
      if [ "$#" -gt 0 ]; then
        docker update "$@" "$container" \
          || echo "bcl-iscsi-device-bridge: failed to update cgroup rules for container $container (not running?)" >&2
      fi
    }

    case "$action" in
      add)
        container=$(find_owner_container) || {
          echo "bcl-iscsi-device-bridge: could not determine owner container for $dev ($major:$minor), leaving it without cgroup access" >&2
          exit 0
        }
        printf '%s' "$container" > "$owner_file"
        rule_file="$state_dir/rules-$container"
        touch "$rule_file"
        grep -qxF "$major:$minor" "$rule_file" || echo "$major:$minor" >> "$rule_file"
        apply_rules_for_container "$container"
        ;;
      remove)
        [ -f "$owner_file" ] || exit 0
        container=$(cat "$owner_file")
        rule_file="$state_dir/rules-$container"
        if [ -f "$rule_file" ]; then
          grep -vxF "$major:$minor" "$rule_file" > "$rule_file.tmp" 2>/dev/null || true
          mv "$rule_file.tmp" "$rule_file"
        fi
        rm -f "$owner_file"
        apply_rules_for_container "$container"
        ;;
    esac
  '';
in
{
  options.bcl.role.serverVirt.iscsiDeviceBridge.enable = lib.mkOption {
    type = lib.types.bool;
    default = false;
    description = ''
      Whether to grant serverVirt containers' docker cgroups access to
      host iSCSI-attached block devices (e.g. Longhorn volumes) whose
      owning container is identified by matching the iSCSI session's
      source IP against each container's static `network.address`. Needed
      because these containers have a private tmpfs /dev with no
      udev/mdev, so Longhorn (which mknods its own device node once it can
      actually use the device) would otherwise never get real access to
      the underlying block device. See
      /memories/repo/longhorn-iscsi-device-discovery-container-nodes.md.

      Only takes effect for containers with `network.address` set; has no
      effect if no container defines one.
    '';
  };

  config = lib.mkIf bridgeCfg.enable {
    environment.etc."bcl/iscsi-device-bridge.sh" = {
      text = script;
      mode = "0755";
    };

    systemd.services."bcl-iscsi-device-bridge-add@" = {
      description = "Grant docker cgroup access to newly-attached iSCSI device %i";
      path = [ config.virtualisation.docker.package ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "/etc/bcl/iscsi-device-bridge.sh add %i";
      };
    };

    systemd.services."bcl-iscsi-device-bridge-remove@" = {
      description = "Revoke docker cgroup access for removed iSCSI device %i";
      path = [ config.virtualisation.docker.package ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "/etc/bcl/iscsi-device-bridge.sh remove %i";
      };
    };

    services.udev.extraRules = ''
      ACTION=="add", SUBSYSTEM=="block", KERNEL=="sd[a-z]", TAG+="systemd", ENV{SYSTEMD_WANTS}+="bcl-iscsi-device-bridge-add@%k-$env{MAJOR}-$env{MINOR}.service"
      ACTION=="remove", SUBSYSTEM=="block", KERNEL=="sd[a-z]", TAG+="systemd", ENV{SYSTEMD_WANTS}+="bcl-iscsi-device-bridge-remove@%k-$env{MAJOR}-$env{MINOR}.service"
    '';
  };
}
