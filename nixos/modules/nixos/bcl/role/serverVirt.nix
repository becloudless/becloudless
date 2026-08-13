{ config, lib, pkgs, inputs, ... }:
let
  srvNumber = lib.strings.toInt(builtins.substring ((builtins.stringLength config.networking.hostName) -1)  (-1) config.networking.hostName);
  cfg = config.bcl.role.serverVirt;
  nixvirt = inputs.nixvirt;
  memorySubmodule = lib.types.submodule {
    options = {
      count = lib.mkOption { type = lib.types.int; default = 4; };
      unit = lib.mkOption { type = lib.types.str; default = "GiB"; };
    };
  };
in
{
  options.bcl.role.serverVirt = {
    clusterNumber = lib.mkOption {type = lib.types.int; default = 1;};

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
            default = "vmbr0";
            description = "Network bridge the VM's NIC attaches to.";
          };
          active = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = "Whether the VM should be running.";
          };
        };
      });
      default = {};
      description = ''
        Declarative libvirt VMs (domains) for this host, managed via NixVirt.
        Any VM not listed here will be undefined/removed by NixVirt on activation.
      '';
    };
  };

  ####################

  config = lib.mkMerge [
    { bcl.role.knownRoles = [ "serverVirt" ]; }
    (lib.mkIf (config.bcl.role.name == "serverVirt") {

    bcl.diskSystem.encrypted = true;
    bcl.boot.ssh = true; # give password for disk encryption on boot

    bcl.role.setAdminPassword = true; # being able to log in to console
    security.sudo.wheelNeedsPassword = false;

    virtualisation.libvirt.enable = true; # also enables virtualisation.libvirtd
    virtualisation.libvirt.swtpm.enable = true; # emulated TPM, needed for windows template

    virtualisation.libvirt.connections."qemu:///system".domains =
      lib.mapAttrsToList (name: vm: {
        definition = nixvirt.lib.domain.writeXML (nixvirt.lib.domain.templates.${vm.template} {
          inherit name;
          uuid = vm.uuid;
          memory = vm.memory;
          storage_vol = vm.diskPath;
          install_vol = vm.installIso;
          bridge_name = vm.bridgeName;
        });
        active = vm.active;
      }) cfg.vms;

    # Create missing disk images before libvirtd starts the VMs that need them.
    systemd.services = lib.mapAttrs' (name: vm:
      lib.nameValuePair "serverVirt-vm-disk-${name}" {
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
    ) (lib.filterAttrs (_: vm: vm.diskSize != null) cfg.vms);

    environment.systemPackages = with pkgs; [
      virt-manager
      virtiofsd
      k9s
      ssh-to-age
      mergerfs
    ];

    networking.nameservers = ["192.168.40.12"];
    services.resolved.dnssec = "true";
    networking.firewall.enable = false;

    systemd.network.enable = true;
    systemd.network.networks.net = {
      matchConfig = {
        Name = "en* eth*";
      };
      networkConfig = {
        IgnoreCarrierLoss = true;
        Bridge = "vmbr0";
      };
    };
    systemd.network.netdevs.vmbr0.netdevConfig = {
      Kind = "bridge";
      Name = "vmbr0";
    };
    systemd.network.networks.vmbr0 = {
      matchConfig = {
        Name = "vmbr0";
      };
      networkConfig = {
        IgnoreCarrierLoss = true;
        KeepConfiguration = true;
      };
      address = [
        "192.168.41.${toString cfg.clusterNumber}${toString srvNumber}/22"
      ];
      routes = [
        {
          Gateway = "192.168.40.10";
          GatewayOnLink = true;
        }
      ];
    };
  })
  ];
}
