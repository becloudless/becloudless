{ config, lib, pkgs, ... }:
let
  cfg = config.bcl.virtualbox;
in
{
  options.bcl.virtualbox.enable = lib.mkEnableOption "Enable";

  config = lib.mkIf cfg.enable {
    virtualisation.virtualbox.host.enable = true;
    users.extraGroups.vboxusers.members = [ "n0rad" ];
  };
}
