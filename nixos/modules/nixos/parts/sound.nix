{ config, lib, pkgs, modulesPath, ... }:

let
  cfg = config.bcl.sound;
in
{
  options.bcl.sound.enable = lib.mkEnableOption "Enable";

  config = lib.mkIf cfg.enable {
    services.pulseaudio.enable = false;
    security.rtkit.enable = true;
    services.pipewire = {
      enable = true;
      alsa.enable = true;
      alsa.support32Bit = true;
      pulse.enable = true;
      wireplumber.enable = true;
    };
  };
}
