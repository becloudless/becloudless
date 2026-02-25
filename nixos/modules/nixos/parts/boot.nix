{
  config,
  lib,
  pkgs,
  ...
}:
with lib.bcl;
let
  cfg = config.bcl.boot;
in {
  options.bcl.boot = {
    enable = lib.mkEnableOption "Enable the default settings?";
    quiet = lib.mkEnableOption "Stay quiet";
    plymouth = lib.mkEnableOption "Enable plymouth";
    ssh = lib.mkEnableOption "Enable";
    initrdSSHPrivateKey = lib.mkOption {
      type = lib.types.str;
      description = ''Private key for initrd SSH server.'';
#      default = lib.mkIf cfg.ssh "";
    };
    loader = lib.mkOption {
      type = lib.types.enum [ "efi" "bios" "uboot" ];
      default = "efi";
      description = ''Boot loader type: "efi" for systemd-boot/grub with EFI, "bios" for legacy BIOS with grub, "uboot" for generic-extlinux-compatible (ARM boards).'';
    };
    configurationLimit = lib.mkOption {
      default = 42;
      type = lib.types.int;
      description = ''Number of config to keep'';
    };
  };

  config = lib.mkIf cfg.enable {
    boot = {
      consoleLogLevel = if cfg.quiet then 0 else 4;
      kernelParams = if cfg.plymouth && cfg.quiet then
          [
            "splash"
            "quiet"
            "boot.shell_on_fail"
            "loglevel=3"
            "rd.systemd.show_status=false"
            "rd.udev.log_level=3"
            "udev.log_priority=3"
          ]
        else if cfg.quiet then
          [
            "quiet"
            "boot.shell_on_fail"
            "loglevel=3"
            "rd.systemd.show_status=false"
            "rd.udev.log_level=3"
            "udev.log_priority=3"
          ]
        else
        [];
      loader = {
        timeout = lib.mkForce (if cfg.quiet then 0 else 1);
        systemd-boot = lib.mkIf (cfg.loader == "efi" && (builtins.length config.bcl.disk.devices) == 1) {
          enable = true;
          configurationLimit = 10;
        };
        grub = if (cfg.loader == "bios" || (cfg.loader == "efi" && (builtins.length config.bcl.disk.devices) > 1)) then {
          enable = true;
          efiSupport = cfg.loader == "efi";
          efiInstallAsRemovable = lib.mkIf (cfg.loader == "efi") ((builtins.length config.bcl.disk.devices) > 1); # required to install on multiple disks
          configurationLimit = 10;
#          device = "nodev";
#          theme = "${pkgs.grub-cyberexs}/share/grub/themes/CyberEXS";
        } else {
          enable = false;
        };
        generic-extlinux-compatible = lib.mkIf (cfg.loader == "uboot") {
          enable = true;
          configurationLimit = 10;
        };
        efi.canTouchEfiVariables = lib.mkIf (cfg.loader != "uboot") ((builtins.length config.bcl.disk.devices) <= 1);
      };
      initrd = {
        verbose = !cfg.quiet;
        systemd = {
          enable = true;
          network = config.systemd.network;
          users.root = {
            shell = "/bin/systemd-tty-ask-password-agent";
          };
        };
        kernelModules = config.boot.kernelModules;
        network.ssh = lib.mkIf cfg.ssh {
          enable = true;
          port = 22;
          authorizedKeys = [ "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILvM8t4hXJxjBzrUS5FhAQ/TD9TJscT7CyLKFSOjZjj4 id_ed25519" ];
          # uboot does not support secrets in initrd, so we give a path to have the key in the
          hostKeys = lib.mkIf (cfg.loader != "uboot") [ "/etc/ssh/initrd_ssh_host_ed25519_key" ];
          ignoreEmptyHostKeys = true;
        };
        # postDeviceCommands = lib.mkAfter ''
        #   zfs rollback -r rpool/local/root@blank
        # '';
      };
      plymouth = {
        enable = cfg.plymouth;
#        theme = "bcl";
#        themePackages = with pkgs; [ bcl.plymouth-bcl ];
      };
    };

    # This key is used only in initrd. nix-sops does not support secrets in initrd,
    # and it have to be a dedicated key anyway since boot partition is not encrypted.
    # Also this key have to be set at install because `ssh` setup is run before `environment`
    environment.etc."ssh/initrd_ssh_host_ed25519_key" = lib.mkIf cfg.ssh {
      mode = "0600";
      text = cfg.initrdSSHPrivateKey;
    };
  };
}