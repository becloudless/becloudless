{ config, lib, pkgs, ... }:

{
  config = lib.mkIf (config.bcl.role.name != "") {

    services.getty.helpLine = lib.mkForce "" ;
    services.getty.greetingLine = ''<<< bcl ${config.system.nixos.label} (\m) - \l >>>'';

    nix.settings.experimental-features = [ "nix-command" "flakes" ];

  };
}
