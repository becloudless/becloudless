{ config, lib, pkgs, ... }:

{
  config = lib.mkIf (config.bcl.role.name != "") {

    nix.package = pkgs.nixVersions.nix_2_25; # need >=2.25 with flake path fix

    services.getty.helpLine = lib.mkForce "" ;
    services.getty.greetingLine = ''<<< bcl ${config.system.nixos.label} (\m) - \l >>>'';

    nix.settings.experimental-features = [ "nix-command" "flakes" ];

  };
}
