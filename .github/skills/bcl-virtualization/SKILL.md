---
name: bcl-virtualization
description: "Use when: working on bcl.role.serverVirt / bcl.vm VMs (libvirt via NixVirt), LVM thin pools and VM volumes (bcl.diskSystem lvmPool, extraDisks, persistRoot, bcl.vm.vms.<name>.volumes), aarch64 VM hosts (NixVirt x86_64 hardcoding, binfmt, OVMF), libvirt errors (virt-secret-init-encryption, CPU mode host-passthrough, managed save restore), VM disk missing after reboot (thin_check, lvchange), VLAN bridges stuck in wait-online, iSCSI device bridge for container nodes, VFIO GPU passthrough, virtiofs limits."
---

# VM hosts in bcl (serverVirt, NixVirt, LVM thin)

Read [bcl-nixos](../bcl-nixos/SKILL.md) first. Everything here lives in `nixos/modules/nixos/bcl/role/serverVirt*.nix`, `vm.nix` and `diskSystem.nix`. libvirt errors are runtime-only: `nix eval` and `nix build` do not catch them, only the real `nixvirt.service` run on the host does.

## Storage design

- Host: small fixed-size partition for `/nix` (`bcl.diskSystem.nix.size`, `bcl.diskSystem.nix.format`), the rest of the disk as an LVM PV/VG with a thin pool (`bcl.diskSystem.lvmPool = {}`, defaults `vgName = "vmpool"`, `poolName = "thinpool"`; requires GPT, a single device and a fixed `nix.size`). disko appends `FREE` for a `100%` LV size: write `size = "100%"`. Changing partitioning means a host reinstall, not a switch.
- VM root disk: raw thin LV `/dev/<lvmVg>/<vm>` (`bcl.vm.vms.<name>.diskSize`, `lvmVg` default `data`, `lvmPool` default `thinpool`), attached as raw virtio-blk (`cache = none`). NixVirt templates hardcode a qcow2 `storage_vol`: pass `storage_vol = null` and prepend your own block disk to `base.devices.disk` before `writeXML` (templates return plain attrsets). `source.dev` accepts any string despite its `typePath` name.
- Extra volumes: `bcl.vm.vms.<name>.volumes.<vol>.size` creates thin LV `<vm>-<vol>`, attached with `serial = <vol>`. Guest side `bcl.diskSystem.extraDisks.<name> = { mountpoint; format; }` matches `/dev/disk/by-id/virtio-<serial>`, so attach order does not matter. `neededForBoot = true` is set for every extra disk (impermanence asserts it for the persist root). `bcl.diskSystem.persistRoot` (default `/nix`) moves the impermanence root, e.g. `/persist` on virtiofs guests.
- Creation/growth is a grow-only oneshot `bcl-vm-lv-<vm>[-<vol>]` before libvirtd (`lvs vg/lv || lvcreate --thin -V size`, else `lvresize` only when growing; compare `lvs -o lv_size --units b --nosuffix` with `numfmt --from=iec`). Growing the virtual disk does not grow the guest partition or filesystem.
- udev rule `SUBSYSTEM=="block", ENV{DM_VG_NAME}=="<vg>", GROUP="kvm", MODE="0660"` per distinct VG lets qemu open the LV.
- Kubernetes persistence dirs are bind-mounted by impermanence unless `config.fileSystems ? "<path>"` exists already (generic check instead of coupling to how the mount was made).
- virtiofs is FUSE: kubelet/cadvisor fails with `could not find device in cached partitions map` and containerd overlayfs cannot mount on it. Guests running kubelet/containerd need real block-backed volumes for `/var/lib/kubelet`, containerd and Longhorn.
- RAM-poor hosts: avoid ZFS zvols (ARC). Rejected options: qcow2 on btrfs (double CoW, no live growth), iSCSI/NBD for same-host VMs.
- Module gotcha: two top-level `fileSystems = ...` or `systemd.services = ...` in the same `config` attrset is a duplicate attribute (not merged like separate modules). Combine with `//`.

## LVM thin boot activation

Symptom: after a reboot a VM root LV is inactive (`lvs` Attr `-`), libvirt cannot start the domain, pool shows `a`.
- Cause 1: no `thin_check` on NixOS (`execvp failed`, unit `lvm-activate-<vg>` `NOTINSTALLED`). Fix: `services.lvm.boot.thin.enable = true`.
- Cause 2 (even with that fixed): the initrd `lvm-activate-<vg>` is killed by switch-root during `thin_check`, the pool is active but VM LVs are not. Fix: the `bcl-vm-lv-<vm>` script ends with `lvchange -ay <vg>/<vm>`.
- Symptom in that case: `nixvirt.service` fails with `libvirt_iohelper ... unexpected fatal signal 13` (restoring `/var/lib/libvirt/qemu/save/<vm>.save`); the real error is `Cannot access storage file '/dev/<vg>/<vm>'` in the journal.
- Immediate remediation: `sudo lvchange -ay <vg>/<lv>; sudo systemctl restart nixvirt` (or `virsh start <vm>`; declarative `active = true` does not retry a failed autostart).
- Managed saves (libvirt-guests default suspend on shutdown) restore with the old live XML and the old qemu store path (`Cannot check QEMU binary ...` after a nixpkgs bump). Use `virtualisation.libvirtd.onShutdown = "shutdown"` (+ `parallelShutdown`), and remove existing saves with `virsh managedsave-remove <vm>`. The restart watcher unit is ordered after `libvirt-guests`.

## libvirt secret unit (virt-secret-init-encryption)

libvirt ships `virt-secret-init-encryption.service`, which calls `systemd-creds encrypt` and hard-fails on hosts with no TPM2 and a tmpfs root (`TPM2 not available and host key located on temporary file system`); `nixos-rebuild switch` exits 4. Disks that are plain LVs do not need it.
- Do NOT set `systemd.services.virt-secret-init-encryption.enable = false`: that masks the unit, and `libvirtd.service` has `Requires=` on it, so later explicit restarts of libvirtd/nixvirt fail with `Unit ... is masked` while boot still works (the failure only appears much later).
- Do: override as a no-op drop-in:
  ```nix
  virt-secret-init-encryption = {
    overrideStrategy = "asDropin";
    serviceConfig.ExecStart = lib.mkForce "${pkgs.coreutils}/bin/true";
  };
  ```
  General rule: never mask a unit that another unit `Requires=`; make it a harmless no-op.
- Found with `systemctl --failed` and `journalctl -b -p err` on the host; grepping nixpkgs modules is a dead end because the trigger is in the package's own unit.

## aarch64 VM hosts (NixVirt)

- NixVirt's flake hardcodes `packages = import nixpkgs { system = "x86_64-linux"; }`, so its helper scripts (`nixvirt-module-helper`, python env) are x86_64-only. A non-x86 host needs `boot.binfmt.emulatedSystems = lib.mkIf (system != "x86_64-linux") [ "x86_64-linux" ]` in the module that enables libvirt, otherwise building the host closure fails with a chain of `Required system: 'x86_64-linux'` errors (`builder.pl.drv`, `nixvirt-module-helper.drv`, ...). Bootstrap: the first deploy must be cross-built from an x86_64 workstation with `boot.binfmt.emulatedSystems = [ "aarch64-linux" ]`; afterwards self-rebuilds (autoUpgrade) work natively.
- Native ARM guests need overrides on top of the base template (inside `lib.optionalAttrs isAarch64`), as flat siblings under `os`/`devices`: `os.arch = "aarch64"`, `os.machine = "virt"`; UEFI only (`os.loader = { readonly; type = "pflash"; path = pkgs.OVMF.fd.firmware; }`, `os.nvram = { template = pkgs.OVMF.fd.variables; path = ".../${name}_VARS.fd"; }`); `devices.emulator = "${pkgs.qemu}/bin/qemu-system-aarch64"`; add a `qemu-xhci` USB controller (no implicit USB on `virt`); `video.model.type = "virtio"` (no QXL); `input` as usb tablet + keyboard (no PS/2). Also `virtualisation.libvirtd.package = lib.mkForce pkgs.libvirt`.
- Errors such as `CPU mode 'host-passthrough' for aarch64 kvm domain on x86_64 host` while `uname -m`, `/dev/kvm` and the capabilities cache are all correct mean stale daemon state: fully restart libvirtd (`systemctl restart libvirtd`), then `nixvirt.service`. No code change needed. When a libvirt message contradicts verified host facts, restart the daemon before reading libvirt source.
- Deploy with native build on the target to avoid emulated builds of firmware: `nixos-rebuild switch --flake .#<host> --override-input bcl "git+file://<abs>/becloudless?dir=nixos" --build-host <user>@<host> --target-host <user>@<host> --use-remote-sudo`. After `--target-host` deploys, scan the whole output for `nix-copy-closure ... non-zero` / `lacks a signature by a trusted key` (the global role sets `nix.settings.trusted-users = [ "root" "@wheel" ]` for this) and confirm `readlink -f /nix/var/nix/profiles/system` on the target.

## VLAN bridges and wait-online

Per-VLAN bridges (`br<id>`) intentionally have no address on the host; their networkd setup state stays `configuring` forever (only a `foreign` link-local address) and `systemd-networkd-wait-online` times out although the host is online. Fix: `linkConfig.RequiredForOnline = false` on those networks. Diagnose with `SYSTEMD_LOG_LEVEL=debug systemd-networkd-wait-online --timeout=8` (prints which link is `being processed ... configuring`) and compare `networkctl status <if> --json=pretty` with a working link.

## Container nodes (Kubernetes node as a container) and iSCSI

- Longhorn on a node that is a Docker container with its own network namespace fails: `iscsid` dies registering the session over NETLINK_ISCSI (`sendmsg ... ECONNREFUSED`) because the kernel iSCSI transport only listens in the host netns. Diagnose with `strace -f -e trace=network,socket iscsid -f -n -d 8` inside the container. Options: host networking for the node container (breaks macvlan designs), exclude such nodes from volume scheduling (taint/affinity), or run `iscsid` on the host (`services.openiscsi`) plus the device bridge below.
- Longhorn finds devices through `iscsiadm -m session -P 3` + sysfs and creates `/dev/longhorn/<vol>` itself with `mknod`; a private tmpfs `/dev` is fine. What blocks I/O is the container device cgroup. `bcl.role.serverVirt.iscsiDeviceBridge.enable` runs a udev rule on `sd[a-z]` add/remove, resolves the owning container from the iSCSI connection `local_ipaddr` and calls `docker update --device-cgroup-rule='b <maj>:<min> rwm'`. `docker update --device-cgroup-rule` REPLACES the whole list, so the script keeps a per-container state file and passes every desired rule each time; the last grant is not revoked when the list becomes empty.
- `--pid=host` does not work with s6-overlay images (`s6-overlay-suexec: fatal: can only run as pid 1`, the container crash-loops). Longhorn's instance manager locates `iscsid` by scanning `/host/proc`, so a host `iscsid` is only discoverable with a shared pid namespace: either change the image entrypoint (tini + supervisor) or avoid container nodes for storage.
- A static route to a pod CIDR through a macvlan parent bridge that has no IPv4 address needs `onlink` (`Nexthop has invalid gateway`). In systemd units use absolute `${pkgs.iproute2}/bin/ip` when `path` does not resolve.

## VFIO GPU passthrough: check dmesg first

For new Intel iGPUs (Arrow Lake-P, device `8086:7dd1`, driver `xe`), passthrough to a guest froze at boot: `vfio_container_dma_map(...) = -22` / `PCI peer-to-peer transactions on BARs are not supported`. GuC firmware submission needs BAR peer-to-peer DMA, which VFIO/QEMU do not support; adding the MEI device does not help (no FLR either) and SR-IOV was unavailable (`Support for SR-IOV is not available`). Before investing, look for that dmesg line. The `pciDevices`/`hostdev` code in `serverVirtVms.nix` stays valid for hardware without this limit. Detect a frozen guest by taking two `virsh screenshot <vm> out.ppm --screen 0` six seconds apart: identical frames mean frozen.
