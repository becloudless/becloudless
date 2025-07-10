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
    efi = lib.mkOption {
       type = lib.types.bool;
       default = true;
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
        timeout = if cfg.quiet then 0 else 1;
        systemd-boot = lib.mkIf (cfg.efi && (builtins.length config.bcl.disk.devices) == 1) {
          enable = true;
          configurationLimit = 10;
        };
        grub = lib.mkIf (!cfg.efi || (builtins.length config.bcl.disk.devices) > 1) {
          enable = true;
          efiSupport = cfg.efi;
          efiInstallAsRemovable = lib.mkIf cfg.efi ((builtins.length config.bcl.disk.devices) > 1); # required to install on multiple disks
          configurationLimit = 10;
#          device = "nodev";
#          theme = "${pkgs.grub-cyberexs}/share/grub/themes/CyberEXS";
        };
        efi.canTouchEfiVariables = (builtins.length config.bcl.disk.devices) <= 1;
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
          hostKeys = [ "/etc/ssh/initrd_ssh_host_ed25519_key" ];
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
    environment.etc."ssh/initrd_ssh_host_ed25519_key" = {
      mode = "0600";
      text = ''
          -----BEGIN OPENSSH PRIVATE KEY-----
          SOMETHING
          -----END OPENSSH PRIVATE KEY-----
        '';
    };
  };
}