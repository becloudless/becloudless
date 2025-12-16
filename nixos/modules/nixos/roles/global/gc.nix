{ config, lib, ... }:

{
  config = lib.mkIf (config.bcl.role.name != "") {
    nix.gc.automatic = true;
    nix.gc.dates = "03:15";
    nix.gc.options = "-d";
  };
}
