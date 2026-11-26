{ config, lib, ... }:

let
  cfg = config.bcl.role.gc;
in
{
  options.bcl.role.gc.keepDays = lib.mkOption {
    type = lib.types.ints.positive;
    default = 30;
    description = "Number of days the old system generations (and what they reference) are kept by the nightly garbage collection of the nix store.";
  };

  config = lib.mkIf (config.bcl.role.name != "") {
    nix.gc.automatic = true;
    nix.gc.dates = "03:15";
    nix.gc.options = "--delete-older-than ${toString cfg.keepDays}d";
  };
}
