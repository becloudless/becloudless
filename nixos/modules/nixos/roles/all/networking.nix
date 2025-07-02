{ config, lib, ... }:

{
  config = lib.mkIf config.bcl.role.enable {
    networking.timeServers = [ "192.168.40.12" ];

    networking.domain = "h.bcl.io";

    # legacy
    networking.useDHCP = lib.mkForce false;
  };
}
