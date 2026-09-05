{ config, lib, pkgs, inputs, ... }:
let
  cfg = config.bcl.role.serverVirt;
  nixvirt = inputs.nixvirt;
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

    # NixVirt's own flake hardcodes `import nixpkgs { system = "x86_64-linux"; }`
    # at the top level and uses that same instance for ITS OWN default
    # `virtualisation.libvirt.package` (== `cfg.package` in NixVirt's
    # modules.nix), which its module then feeds into
    # `virtualisation.libvirtd.package` via `lib.mkDefault`. Since nothing
    # here overrode that, on a non-x86_64-linux host (e.g. aarch64 orangepi
    # boards) this made the ENTIRE libvirtd DAEMON itself an x86_64-linux
    # binary, silently run under QEMU user-mode/binfmt emulation at runtime
    # (confirmed via ELF header: EM_X86_64) - not just a build-time
    # inconvenience for NixVirt's small helper scripts, but the actual
    # long-running libvirtd process on every boot. This is fragile: observed
    # intermittent capability-probing crashes
    # ("qemu_plugin_vcpu_init__async: assertion failed") from an
    # emulated-x86_64 libvirtd in turn spawning a native aarch64
    # qemu-system-x86_64 to probe its capabilities - nested/cross emulation
    # for no reason, since we only ever run aarch64 (or matching-host-arch)
    # VMs here.
    #
    # IMPORTANT: override `virtualisation.libvirtd.package` DIRECTLY here,
    # NOT `virtualisation.libvirt.package` (NixVirt's own `cfg.package`)!
    # `cfg.package` is ALSO used by NixVirt's own systemd.services.nixvirt
    # script to build its Python-bindings helper
    # (`moduleHelperFile cfg.package` -> `packages.libvirt.override { inherit
    # libvirt; }`, where `packages` is NixVirt's own hardcoded x86_64-linux
    # nixpkgs instance). Overriding `cfg.package` to a NATIVE aarch64 build
    # makes that helper try to link an x86_64 Python C-extension against an
    # aarch64 libvirt.so -> `ld.bfd: skipping incompatible .../libvirt.so
    # when searching for -lvirt` / `cannot find -lvirt`. Overriding only
    # `virtualisation.libvirtd.package` fixes the actual daemon's
    # architecture while leaving NixVirt's own helper-script build
    # self-consistent (still x86_64, still emulated, but that's just a tiny
    # short-lived script, not the long-running daemon).
    virtualisation.libvirtd.package = lib.mkForce pkgs.libvirt;

    # NixVirt's own flake hardcodes `import nixpkgs { system = "x86_64-linux"; }`
    # for the helper scripts it wires into `systemd.services.nixvirt`
    # (nixvirt-module-helper, virtdeclare), regardless of the host's actual
    # system. On a non-x86_64-linux host (e.g. aarch64 orangepi boards) this
    # makes `nixos-rebuild`/autoUpgrade fail with "platform mismatch: Required
    # system: 'x86_64-linux', Current system: 'aarch64-linux'" unless the
    # host can emulate x86_64-linux locally.
    boot.binfmt.emulatedSystems = lib.mkIf (pkgs.stdenv.hostPlatform.system != "x86_64-linux") [ "x86_64-linux" ];

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
              storage_vol = null; # root disk attached below as a raw LVM block device
              install_vol = if vm.installIso != null then vm.installIso else cfg.defaultIso;
              bridge_name = vm.bridgeName;
              virtio_video = false; # use QXL video with SPICE listening on 127.0.0.1
            };
          in
          base // {
            os = base.os // {
              boot = [ { dev = "hd"; } { dev = "cdrom"; } ];
            };
            devices = base.devices // {
              disk = [{
                type = "block";
                device = "disk";
                driver = { name = "qemu"; type = "raw"; cache = "none"; discard = "unmap"; };
                source = { dev = "/dev/data/${name}"; };
                target = { dev = "vda"; bus = "virtio"; };
              }] ++ base.devices.disk;
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
