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
          finalDomainDef = if vm.guestNix != null then
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
        in {
          definition = nixvirt.lib.domain.writeXML finalDomainDef;
          active = vm.active;
        }
      ) cfg.vms;

    # Create missing disk images before libvirtd starts the VMs that need them.
    systemd.services =
      lib.mapAttrs' (name: vm:
        lib.nameValuePair "bcl-vm-disk-${name}" {
          description = "Create qcow2 disk image for VM ${name}";
          wantedBy = [ "multi-user.target" ];
          before = [ "libvirtd.service" ];
          unitConfig.ConditionPathExists = "!${vm.diskPath}";
          serviceConfig.Type = "oneshot";
          path = [ pkgs.qemu ];
          script = ''
            mkdir -p "$(dirname ${vm.diskPath})"
            qemu-img create -f qcow2 ${vm.diskPath} ${vm.diskSize}
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
      ) vmsWithGuestNix;
  };
}
