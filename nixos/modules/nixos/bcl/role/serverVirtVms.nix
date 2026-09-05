{ config, lib, pkgs, ... }:
let
  cfg = config.bcl.role.serverVirt;
  # Instantiated with the host's own native `pkgs`, not NixVirt's own
  # hardcoded x86_64-linux nixpkgs instance - see
  # ../../../packages/nixvirt/VENDORED.md for why this is vendored rather
  # than used as a flake input.
  nixvirt = { lib = import ../../../../packages/nixvirt/lib.nix { packages = pkgs; }; };
  unitSuffixes = { K = "KiB"; M = "MiB"; G = "GiB"; T = "TiB"; };
  parseMemory = str:
    let
      m = builtins.match "([0-9]+)([KMGT])" str;
    in
    if m == null then
      throw "bcl.role.serverVirt.vms.<name>.memory: \"${str}\" must match <number><K|M|G|T>, e.g. \"4096M\" or \"4G\""
    else {
      count = lib.toInt (builtins.elemAt m 0);
      unit = unitSuffixes.${builtins.elemAt m 1};
    };
in
{
  options.bcl.role.serverVirt = {
    defaultIso = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "Default ISO image to attach as an install CDROM for VMs that don't set their own installIso.";
    };
    vms = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule {
        options = {
          uuid = lib.mkOption {
            type = lib.types.str;
            description = "Libvirt domain UUID (generate once with `uuidgen`, then keep it stable).";
          };
          template = lib.mkOption {
            type = lib.types.enum [ "linux" "windows" ];
            default = "linux";
            description = "Which NixVirt domain template to use.";
          };
          memory = lib.mkOption {
            type = lib.types.str;
            default = "4G";
            description = "Amount of RAM for the VM, as <number><K|M|G|T>, e.g. \"4096M\" or \"4G\".";
          };
          vcpu = lib.mkOption {
            type = lib.types.ints.positive;
            default = 2;
            description = "Number of virtual CPUs for the VM.";
          };
          diskSize = lib.mkOption {
            type = lib.types.str;
            description = "Size of the LVM thin volume backing this VM's root disk (e.g. \"20G\"). Created/grown automatically.";
          };
          installIso = lib.mkOption {
            type = lib.types.nullOr lib.types.path;
            default = null;
            description = "ISO image to attach as an install CDROM, or null to fall back to bcl.role.serverVirt.defaultIso.";
          };
          bridgeName = lib.mkOption {
            type = lib.types.str;
            default = "br0";
            description = ''
              Network bridge the VM's NIC attaches to, e.g. "br0".
            '';
          };
          active = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = "Whether the VM should be running.";
          };
          virtioVideo = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = ''
              Whether to use VirtIO GL-accelerated video (SPICE listen type "none",
              file-descriptor passing only). Set to false (default) to use
              QXL video with SPICE listening on 127.0.0.1, which is required
              for remote console access via qemu+ssh (e.g. virt-manager).
            '';
          };
        };
      });
      default = {};
      description = ''
        Declarative libvirt VMs (domains) managed via NixVirt.
        Any VM not listed here will be undefined/removed by NixVirt on activation.
      '';
    };
  };

  ####################

  config = lib.mkIf (cfg.vms != {}) {
    virtualisation.libvirt.enable = true; # also enables virtualisation.libvirtd
    virtualisation.libvirt.swtpm.enable = true; # emulated TPM, needed for windows template

    # Without this, /etc/lvm/lvm.conf's thin_check_executable defaults to the
    # FHS path "/usr/sbin/thin_check", which doesn't exist on NixOS. This
    # makes `vgchange -aay` (run by the lvm2-activation-generator systemd
    # units at boot) fail on thin volumes, so VM root disks (thin LVs) are
    # left inactive after a reboot even though the thin pool itself is
    # activated (its device-mapper devices don't depend on thin_check).
    services.lvm.boot.thin.enable = true;

    # Let libvirtd's qemu process (group "kvm") open the LVM thin volumes used as VM root disks.
    services.udev.extraRules = ''
      SUBSYSTEM=="block", ENV{DM_VG_NAME}=="data", GROUP="kvm", MODE="0660"
    '';



    virtualisation.libvirt.connections."qemu:///system".domains =
      lib.mapAttrsToList (name: vm: {
        definition = nixvirt.lib.domain.writeXML (
          let
            base = nixvirt.lib.domain.templates.${vm.template} {
              inherit name;
              uuid = vm.uuid;
              memory = parseMemory vm.memory;
              vcpu = { count = vm.vcpu; };
              storage_vol = null; # root disk attached below as a raw LVM block device
              install_vol = if vm.installIso != null then vm.installIso else cfg.defaultIso;
              bridge_name = vm.bridgeName;
              virtio_video = false; # use QXL video with SPICE listening on 127.0.0.1
            };
          in
          base // {
            os = base.os // {
              boot = [ { dev = "hd"; } { dev = "cdrom"; } ];
            } // lib.optionalAttrs pkgs.stdenv.hostPlatform.isAarch64 {
              # NixVirt's own templates (templates/domain/base.nix) hardcode
              # `os.type.arch = "x86_64"`, `machine = "q35"|"pc"`, and
              # `devices.emulator = ".../qemu-system-x86_64"` unconditionally,
              # regardless of the host's actual architecture. On an aarch64
              # host this means every VM defined via these templates is
              # ALWAYS an x86_64 guest requiring slow QEMU TCG software
              # emulation (no KVM acceleration possible cross-arch), which is
              # both wrong (we want native aarch64 guests here) and was
              # additionally crashing during libvirt's capability-probing at
              # domain-definition time. Override to a genuine aarch64/"virt"
              # machine-type guest using the native qemu-system-aarch64
              # binary (see devices.emulator override below).
              arch = "aarch64";
              machine = "virt";
              # aarch64 "virt" machines have no legacy BIOS, only UEFI - need
              # an explicit pflash loader/nvram, unlike x86_64 where NixVirt's
              # templates rely on OVMF/`os.firmware` autoselection. Reuse
              # `pkgs.OVMF`, the exact same package NixOS's own qemu-vm.nix
              # (NixOS VM tests) uses for EFI firmware+variables - it's a
              # cross-arch-aware edk2 build that produces AAVMF (ArmVirtQemu)
              # firmware/variables when built for aarch64, rather than a
              # separate/adhoc firmware source.
              loader = { readonly = true; type = "pflash"; path = pkgs.OVMF.fd.firmware; };
              nvram = {
                template = pkgs.OVMF.fd.variables;
                path = "/var/lib/libvirt/qemu/nvram/${name}_VARS.fd";
              };
            };
            devices = base.devices // {
              disk = [{
                type = "block";
                device = "disk";
                driver = { name = "qemu"; type = "raw"; cache = "none"; discard = "unmap"; };
                source = { dev = "/dev/data/${name}"; };
                target = { dev = "vda"; bus = "virtio"; };
              }] ++ (
                # NixVirt's templates (templates/domain/base.nix) attach the
                # install CDROM via bus="sata" (q35's cdtarget). aarch64
                # "virt" guests use AAVMF/ArmVirtQemu firmware, which
                # (unlike x86_64 OVMF) has no AHCI/SATA driver at all - the
                # CDROM is never visible as a bootable device, so the VM
                # starts but silently never boots the install ISO. Move it
                # to virtio-scsi instead (see the matching "scsi" controller
                # added below), which ArmVirtQemu does support.
                if pkgs.stdenv.hostPlatform.isAarch64 then
                  map
                    (d: if d.device == "cdrom" then d // { target = { dev = "sda"; bus = "scsi"; }; } else d)
                    base.devices.disk
                else
                  base.devices.disk
              );
            } // lib.optionalAttrs pkgs.stdenv.hostPlatform.isAarch64 {
              emulator = "${pkgs.qemu}/bin/qemu-system-aarch64";
              # Unlike q35/pc, the aarch64 "virt" machine type has no
              # implicit USB controller - libvirt refuses to define a domain
              # whose devices (base.nix's `input` tablet and `redirdev` SPICE
              # USB channels, both bus="usb") reference USB without one
              # ("unsupported configuration: USB is disabled for this
              # domain, but USB devices are present in the domain XML").
              # Add an explicit xHCI USB controller, as libvirt/QEMU expect
              # for aarch64 "virt" guests. Also add a virtio-scsi controller
              # for the install CDROM (moved off bus="sata" above, since
              # ArmVirtQemu firmware has no AHCI driver).
              controller = (base.devices.controller or [ ]) ++ [
                { type = "usb"; model = "qemu-xhci"; }
                { type = "scsi"; model = "virtio-scsi"; }
              ];
              # base.nix's QXL video model (chosen above via virtio_video =
              # false, for SPICE listening on 127.0.0.1 without needing GL)
              # is an x86-specific legacy VGA-compatible PCI device - aarch64
              # "virt" machines have no legacy VGA, so libvirt rejects it
              # ("domain configuration does not support video model
              # 'qxl'"). Use virtio-gpu instead, which aarch64 supports.
              video = { model = { type = "virtio"; heads = 1; primary = true; }; };
              # base.nix's mouse/keyboard use bus="ps2" (legacy PS/2
              # controller, another x86-specific device absent on aarch64
              # "virt" machines: "ps2 is not supported by this QEMU
              # binary"). Move them to the USB controller added above
              # (tablet already uses USB).
              input = [
                { type = "tablet"; bus = "usb"; }
                { type = "keyboard"; bus = "usb"; }
              ];
              # aarch64 "virt" guests have no legacy VGA text mode, so
              # nothing is ever shown on the SPICE video output until the
              # guest OS's own virtio-gpu driver initializes (10-20+ seconds
              # into boot) - firmware, GRUB, and early kernel messages are
              # all invisible on video. This is because ACPI's SPCR table
              # advertises a pl011 serial UART as the primary console, so
              # that's where all early output actually goes. Without an
              # explicit serial/console device, none of this is viewable at
              # all. Add the standard aarch64 pl011 serial + its pty
              # console, so all boot output (firmware/GRUB/kernel, well
              # before video comes up) can be viewed via `virsh console`.
              serial = {
                type = "pty";
                target = { type = "system-serial"; port = 0; model = { name = "pl011"; }; };
              };
              console = {
                type = "pty";
                target = { type = "serial"; port = 0; };
              };
            };
          }
        );
        active = vm.active;
      }) cfg.vms;

    # Create or grow (never shrink) the LVM thin volume backing each VM's root disk,
    # before libvirtd starts the VMs that need them.
    systemd.services = (lib.mapAttrs' (name: vm:
      lib.nameValuePair "bcl-vm-lv-${name}" {
        description = "Create/grow LVM thin volume for VM ${name}";
        wantedBy = [ "multi-user.target" ];
        before = [ "libvirtd.service" ];
        serviceConfig.Type = "oneshot";
        path = [ pkgs.lvm2 pkgs.coreutils ];
        script = ''
          set -e

          # lvm2's autoactivation-generator (lvm-activate-data.service, run at
          # boot on "PV online" udev events) can occasionally have its own
          # `vgchange -aay` interrupted mid-thin_check (observed via
          # journalctl: "wait4 child process ... failed: Interrupted system
          # call" / "Check of pool data/thinpool failed" / "device-mapper:
          # remove ioctl on (major:minor) failed: Device or resource busy").
          # This leaves the pool's private component LVs
          # (thinpool_tdata/thinpool_tmeta) stuck ACTIVE while the public
          # thinpool LV itself never gets activated. LVM then refuses ANY
          # further activation of the pool ("Activation of logical volume
          # data/thinpool is prohibited while logical volume
          # data/thinpool_tmeta is active."), which in turn blocks
          # lvcreate/lvresize below until the strays are cleared. Self-heal
          # this before touching the pool.
          thinpoolOutput=$(lvchange -ay data/thinpool 2>&1) || true
          if echo "$thinpoolOutput" | grep -q "is prohibited while logical volume"; then
            echo "$thinpoolOutput" >&2
            echo "Detected stray-active thin pool component LV(s) blocking activation of data/thinpool; deactivating strays and retrying..." >&2
            lvchange -an data/thinpool_tdata data/thinpool_tmeta
            lvchange -ay data/thinpool
          fi

          if ! lvs "data/${name}" >/dev/null 2>&1; then
            lvcreate --yes -V ${vm.diskSize} -n "${name}" --thinpool="thinpool" "data"
          else
            current=$(lvs --noheadings --units b --nosuffix -o lv_size "data/${name}" | tr -d ' ')
            target=$(numfmt --from=iec ${vm.diskSize})
            if [ "$target" -gt "$current" ]; then
              lvresize -L ${vm.diskSize} "data/${name}"
            fi
          fi
        '';
      }
    ) cfg.vms) // {
      # libvirt ships virt-secret-init-encryption.service, which on first
      # libvirtd start generates a random secret and encrypts it via
      # `systemd-creds encrypt` (default "auto" key selection) into
      # /var/lib/libvirt/secrets/secrets-encryption-key. This is only needed
      # for libvirt's "secret" objects (e.g. LUKS passphrases referenced by
      # a domain's disk XML), which we don't use here (VM root disks are
      # plain LVM thin volumes, no libvirt secrets involved). On hosts with
      # a tmpfs root (impermanence) and no TPM2 (e.g. aarch64 orangepi
      # boards), systemd-creds' "auto" mode has neither a TPM2 nor a
      # persistent host key to encrypt with, so it fails with "TPM2 not
      # available and host key located on temporary file system, no
      # encryption key available.", which nixos-rebuild switch treats as a
      # hard failure of the whole switch (exit status 4).
      #
      # NOTE: don't `enable = false` (mask) this unit - libvirtd.service
      # itself has `Requires=`+`After=virt-secret-init-encryption.service`,
      # and starting a *masked* required unit as part of a fresh systemd
      # transaction (e.g. `systemctl restart libvirtd`/anything that pulls
      # libvirtd in, like this module's own nixvirt.service) fails outright
      # with "Unit virt-secret-init-encryption.service is masked." (this
      # only went unnoticed at boot because boot's initial transaction is
      # more lenient about Requires= on masked units than an explicit/later
      # restart is).
      #
      # NOTE #2: don't turn this into a no-op (e.g. `bin/true`) either -
      # libvirtd.service's OWN unit (`LoadCredentialEncrypted=
      # secrets-encryption-key:/var/lib/libvirt/secrets/secrets-encryption-key`)
      # hard-requires that encrypted-credential file to exist and be
      # loadable; skipping its creation makes libvirtd itself fail at
      # startup with "Failed to set up credentials: No such file or
      # directory" / "Failed at step CREDENTIALS spawning .../libvirtd".
      # So the file must genuinely be created - just not with `--with-key=auto`
      # (which requires TPM2/persistent host key). `--with-key=null` stores
      # the credential without real encryption (fine here: we don't use any
      # libvirt "secret" objects, so this key is never actually used to
      # protect anything sensitive).
      #
      # NOTE #3: this unit's main ExecStart comes from libvirt's own shipped
      # unit file (via `systemd.packages`), not a NixOS-authored one, so
      # our drop-in's `serviceConfig.ExecStart` only APPENDS a second
      # ExecStart= line rather than replacing the first - systemd runs
      # multiple ExecStart= lines in sequence, so the original (failing on
      # TPM2-less tmpfs-root hosts) would still run first. The empty ""
      # entry is required to clear the inherited ExecStart list before
      # adding ours (systemd unit-file semantics: an empty ExecStart=
      # resets any previously defined ExecStart= commands).
      virt-secret-init-encryption = {
        overrideStrategy = "asDropin";
        serviceConfig.ExecStart = lib.mkForce [
          ""
          ''
            ${pkgs.bash}/bin/sh -c 'umask 0077 && (${pkgs.coreutils}/bin/dd if=/dev/random status=none bs=32 count=1 | ${pkgs.systemd}/bin/systemd-creds encrypt --with-key=null --name=secrets-encryption-key - /var/lib/libvirt/secrets/secrets-encryption-key)'
          ''
        ];
      };
    };
  };
}
