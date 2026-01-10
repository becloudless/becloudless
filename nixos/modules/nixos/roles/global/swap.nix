{ config, lib, pkgs, ... }:

{
  config = lib.mkIf (config.bcl.role.name != "") {
    boot.kernel.sysctl."vm.swappiness" = 10;
    swapDevices = [{
      device = "/nix/swapfile";
      size = 5 * 1024;
    }];
  };
}
