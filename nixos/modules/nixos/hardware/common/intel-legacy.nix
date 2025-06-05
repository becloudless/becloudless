{ config, lib, pkgs, modulesPath, ... }:

{
  config = lib.mkIf (config.bcl.hardware.common == "intel-legacy") {
    # TODO this is not inherited when it could be
    nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
    boot.kernelModules = [ "kvm-intel" ];
    hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;


    ###
    ### transcode on client side require `enabled` and not `copy`
    ###

    environment.variables = {
      # required around jellyfin
      # https://github.com/jellyfin/jellyfin-media-player/issues/139#issuecomment-1296781086
      QT_XCB_GL_INTEGRATION = "xcb_egl";
    };

    # nix-shell -p libva-utils --run vainfo
    hardware = {
      graphics = {
        enable = true;
        enable32Bit = true;
        extraPackages = with pkgs; [
          vaapiIntel
          vaapiVdpau
          libvdpau-va-gl
        ];
      };
    };

  };
}
