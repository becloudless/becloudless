{ config, lib, pkgs, ... }:
let
  cfg = config.bcl.docker;
in
{
  options.bcl.docker.enable = lib.mkEnableOption "Enable";

  config = lib.mkIf cfg.enable {
    virtualisation.docker = {
      enable = true;
      rootless = {
        enable = false;
        setSocketVariable = true;
      };
      daemon.settings = {
        data-root = "/nix/var/lib/docker";
        features = {
          containerd-snapshotter = true;
        };
      };
    };

    environment.systemPackages = with pkgs; [
      docker-buildx
    ];
  };
}
