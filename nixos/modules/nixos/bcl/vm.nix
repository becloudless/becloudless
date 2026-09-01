{ config, lib, pkgs, inputs, ... }:
let
  cfg = config.bcl.vm;
  nixvirt = inputs.nixvirt;
  memorySubmodule = lib.types.submodule {
    options = {
      count = lib.mkOption { type = lib.types.int; default = 4; };
      unit = lib.mkOption { type = lib.types.str; default = "GiB"; };
    };
  };
  guestNixSubmodule = lib.types.submodule {
    options = {
      quota = lib.mkOption {
        type = lib.types.str;
        description = ''
          btrfs qgroup size limit (e.g. "20G") applied to this VM's dedicated
          /nix subvolume on the host.
        '';
      };
    };
  };
  # Host-side btrfs subvolume backing a VM's shared /nix (see guestNix below).
  guestNixSubvolPath = name: "/nix/vms/${name}";
  vmsWithGuestNix = lib.filterAttrs (_: vm: vm.guestNix != null) cfg.vms;
  volumeSubmodule = lib.types.submodule {
    options = {
      size = lib.mkOption {
        type = lib.types.str;
        description = ''
          Virtual size (e.g. "20G") of a thin logical volume created in the
          host's `bcl.diskSystem.lvmPool`, attached to this VM as a raw
          virtio-blk block device identified in the guest by serial number
          (matching the volume's attribute name) - see
          `bcl.diskSystem.extraDisks` on the guest side.
        '';
      };
    };
  };
  lvName = vmName: volName: "${vmName}-${volName}";
  # vda is the main qcow2 disk; extra volumes get vdb, vdc, ...
  volumeTargetDev = index: "vd" + builtins.substring index 1 "bcdefghijklmnopqrstuvwxyz";
  vmsWithVolumes = lib.filterAttrs (_: vm: vm.volumes != { }) cfg.vms;
in
{
  options.bcl.vm = {
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
            type = memorySubmodule;
            default = { count = 4; unit = "GiB"; };
            description = "Amount of RAM for the VM.";
          };
          diskPath = lib.mkOption {
            type = lib.types.path;
            description = "Path to the qcow2 disk image backing this VM.";
          };
          diskSize = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            description = "If set (e.g. \"20G\"), create diskPath as a new qcow2 image of this size when it doesn't already exist.";
          };
          installIso = lib.mkOption {
            type = lib.types.nullOr lib.types.path;
            default = null;
            description = "ISO image to attach as an install CDROM, or null.";
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
          guestNix = lib.mkOption {
            type = lib.types.nullOr guestNixSubmodule;
            default = null;
            description = ''
              When set, this VM's entire /nix is a dedicated btrfs subvolume
              on the host's own /nix filesystem (created at
              `/nix/vms/<name>`, quota-limited via btrfs qgroups), shared
              read-write into the guest over virtiofs (mount tag "nix").
              Living on the host's /nix filesystem also lets bees (see
              `services.beesd`) deduplicate store paths shared between the
              host and any such guests, since bees deduplication crosses
              subvolume boundaries within the same filesystem.

              The guest's own NixOS config must mount it, e.g.:
                fileSystems."/nix" = {
                  device = "nix";
                  fsType = "virtiofs";
                  neededForBoot = true;
                };
            '';
          };
          volumes = lib.mkOption {
            type = lib.types.attrsOf volumeSubmodule;
            default = { };
            description = ''
              Extra raw block devices attached to this VM, each backed by a
              dedicated thin logical volume in the host's
              `bcl.diskSystem.lvmPool` (requires it to be set). Useful for
              things that need a real (non-virtiofs) block device in the
              guest, e.g. a /persist volume for kubelet/containerd state, or
              a dedicated disk for Longhorn - see `bcl.diskSystem.extraDisks`
              on the guest side, which mounts them by matching serial number.
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
    virtualisation.libvirtd.qemu.vhostUserPackages = lib.mkIf (vmsWithGuestNix != {}) [ pkgs.virtiofsd ];

    virtualisation.libvirt.connections."qemu:///system".domains =
      lib.mapAttrsToList (name: vm:
        let
          rawDomainDef = nixvirt.lib.domain.templates.${vm.template} {
            inherit name;
            uuid = vm.uuid;
            memory = vm.memory;
            storage_vol = vm.diskPath;
            install_vol = vm.installIso;
            bridge_name = vm.bridgeName;
            virtio_video = false; # use QXL video with SPICE listening on 127.0.0.1
          };
          domainDef = rawDomainDef // {
            # Boot from disk first, only falling back to the CDROM (install
            # ISO) if the disk has no bootable system yet - standard
            # BIOS/UEFI boot order semantics (each entry tried in turn until
            # one succeeds), instead of NixVirt's default of always booting
            # the CDROM first.
            os = rawDomainDef.os // { boot = [ { dev = "hd"; } { dev = "cdrom"; } ]; };
          };
          domainDefWithGuestNix = if vm.guestNix != null then
            domainDef // {
              # Required for virtiofs: guest and virtiofsd share memory.
              memoryBacking = {
                source = { type = "memfd"; };
                access = { mode = "shared"; };
              };
              devices = domainDef.devices // {
                filesystem = [
                  {
                    type = "mount";
                    accessmode = "passthrough";
                    driver = { type = "virtiofs"; };
                    source = { dir = guestNixSubvolPath name; };
                    target = { dir = "nix"; };
                  }
                ];
              };
            }
          else domainDef;
          volumeDisks = lib.imap0 (index: volName: {
            type = "block";
            device = "disk";
            driver = { name = "qemu"; type = "raw"; cache = "none"; };
            source = { dev = "/dev/${config.bcl.diskSystem.lvmPool.vgName}/${lvName name volName}"; };
            target = { dev = volumeTargetDev index; bus = "virtio"; };
            serial = volName;
          }) (lib.attrNames vm.volumes);
          finalDomainDef = if vm.volumes != { } then
            domainDefWithGuestNix // {
              devices = domainDefWithGuestNix.devices // {
                disk = domainDefWithGuestNix.devices.disk ++ volumeDisks;
              };
            }
          else domainDefWithGuestNix;
        in {
          definition = nixvirt.lib.domain.writeXML finalDomainDef;
          active = vm.active;
        }
      ) cfg.vms;

    # Create missing disk images (and grow existing ones) before libvirtd
    # starts the VMs that need them. Re-run automatically whenever diskSize
    # changes, since that value is embedded in the script below and thus
    # changes the unit's definition (triggering a restart on switch).
    # Shrinking is never done automatically (data-loss risk); if the target
    # size is smaller than the current image size, we just log and skip.
    systemd.services =
      lib.mapAttrs' (name: vm:
        lib.nameValuePair "bcl-vm-disk-${name}" {
          description = "Create/resize qcow2 disk image for VM ${name}";
          wantedBy = [ "multi-user.target" ];
          before = [ "libvirtd.service" ];
          serviceConfig.Type = "oneshot";
          path = [ pkgs.qemu pkgs.jq pkgs.coreutils ];
          script = ''
            mkdir -p "$(dirname ${vm.diskPath})"
            if [ ! -e ${vm.diskPath} ]; then
              qemu-img create -f qcow2 ${vm.diskPath} ${vm.diskSize}
            else
              current_bytes=$(qemu-img info --output=json ${vm.diskPath} | jq -r '."virtual-size"')
              target_bytes=$(numfmt --from=iec ${vm.diskSize})
              if [ "$target_bytes" -gt "$current_bytes" ]; then
                echo "Growing disk image ${vm.diskPath} for VM ${name} to ${vm.diskSize}"
                qemu-img resize ${vm.diskPath} ${vm.diskSize}
              elif [ "$target_bytes" -lt "$current_bytes" ]; then
                echo "bcl.vm.vms.${name}.diskSize (${vm.diskSize}) is smaller than the current disk image size; refusing to shrink automatically" >&2
              fi
            fi
          '';
        }
      ) (lib.filterAttrs (_: vm: vm.diskSize != null) cfg.vms)
      //
      # Create and quota-limit the host btrfs subvolume backing each VM's
      # shared /nix, before libvirtd starts the VM that needs it.
      lib.mapAttrs' (name: vm:
        lib.nameValuePair "bcl-vm-nix-subvol-${name}" {
          description = "Create quota-limited btrfs subvolume for VM ${name}'s /nix";
          wantedBy = [ "multi-user.target" ];
          before = [ "libvirtd.service" ];
          unitConfig.RequiresMountsFor = "/nix";
          unitConfig.ConditionPathExists = "!${guestNixSubvolPath name}";
          serviceConfig.Type = "oneshot";
          path = [ pkgs.btrfs-progs ];
          script = ''
            btrfs quota enable /nix
            mkdir -p "$(dirname ${guestNixSubvolPath name})"
            btrfs subvolume create ${guestNixSubvolPath name}
            btrfs qgroup limit ${vm.guestNix.quota} ${guestNixSubvolPath name}
          '';
        }
      ) vmsWithGuestNix
      //
      # Create (and grow-only resize) the thin logical volumes backing each
      # VM's extra block-device volumes, before libvirtd starts the VM that
      # needs them. Re-run automatically whenever a volume's size changes,
      # same rationale as bcl-vm-disk-<name> above.
      builtins.listToAttrs (lib.flatten (lib.mapAttrsToList (name: vm:
        lib.mapAttrsToList (volName: vol:
          let
            vg = config.bcl.diskSystem.lvmPool.vgName;
            pool = config.bcl.diskSystem.lvmPool.poolName;
            lv = lvName name volName;
          in {
            name = "bcl-vm-lv-${name}-${volName}";
            value = {
              description = "Create/resize thin LV for VM ${name}'s ${volName} volume";
              wantedBy = [ "multi-user.target" ];
              before = [ "libvirtd.service" ];
              serviceConfig.Type = "oneshot";
              path = [ pkgs.lvm2 pkgs.coreutils ];
              script = ''
                if ! lvs "${vg}/${lv}" >/dev/null 2>&1; then
                  lvcreate --yes --thin -V ${vol.size} -n ${lv} ${vg}/${pool}
                else
                  current_bytes=$(lvs --noheadings --units b --nosuffix -o lv_size "${vg}/${lv}" | tr -d ' ')
                  target_bytes=$(numfmt --from=iec ${vol.size})
                  if [ "$target_bytes" -gt "$current_bytes" ]; then
                    echo "Growing LV ${vg}/${lv} to ${vol.size}"
                    lvresize -L ${vol.size} "${vg}/${lv}"
                  elif [ "$target_bytes" -lt "$current_bytes" ]; then
                    echo "bcl.vm.vms.${name}.volumes.${volName}.size (${vol.size}) is smaller than the current LV size; refusing to shrink automatically" >&2
                  fi
                fi
              '';
            };
          }
        ) vm.volumes
      ) vmsWithVolumes));

    assertions = [
      {
        assertion = vmsWithVolumes == { } || config.bcl.diskSystem.lvmPool != null;
        message = "bcl.vm.vms.<name>.volumes requires bcl.diskSystem.lvmPool to be set on this host.";
      }
    ];

    # Thin LV block devices need to be accessible to the qemu process
    # libvirtd spawns (group "kvm" by default in NixOS).
    services.udev.extraRules = lib.mkIf (vmsWithVolumes != { }) ''
      SUBSYSTEM=="block", ENV{DM_VG_NAME}=="${config.bcl.diskSystem.lvmPool.vgName}", GROUP="kvm", MODE="0660"
    '';
  };
}
