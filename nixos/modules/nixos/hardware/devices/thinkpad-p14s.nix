{ config, lib, pkgs, modulesPath, ... }:

{
  imports =
    [ (modulesPath + "/installer/scan/not-detected.nix")
    ];

  config = lib.mkIf (config.bcl.hardware.device == "thinkpad-p14s") {
    bcl.hardware.common = "intel";

    boot.initrd.availableKernelModules = [ "xhci_pci" "thunderbolt" "nvme" ];

    ##
    # services.xserver.videoDrivers = ["nvidia"];

    # hardware.nvidia.prime = {
    #   offload = {
      # 		enable = true;
      # 		enableOffloadCmd = true;
      # 	};
      # 	intelBusId = "PCI:0:2:0";
      # 	nvidiaBusId = "PCI:3:0:0";
      # };
    # hardware.nvidia = {
    #   powerManagement = {
    #     enable = true;
    #     finegrained = true;
    #   };
    # };

     powerManagement.cpuFreqGovernor = lib.mkDefault "powersave";

    #
    services.keyd = {
      enable = true;
      keyboards = {
        default = {
          ids = ["*"];
          settings = {
            main = {
              # Make keyboard look like mac one
              leftmeta = "leftalt"; # swap leftmeta with leftalt
              leftalt = "leftmeta"; # swap leftmeta with leftalt
              rightalt = "rightmeta"; # set rightmeta to rightalt
              sysrq = "rightalt"; # set rightalt to printscreen
              pageup = "left";
              pagedown = "right";
            };
          };
        };
      };
    };
  };
}
