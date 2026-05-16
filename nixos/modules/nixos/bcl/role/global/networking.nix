{ config, lib, ... }:

{
  config = lib.mkIf (config.bcl.role.name != "") {
    # TODO
    # networking.timeServers = [ "192.168.40.12" ];

    # networking.domain = "h.test.local";

    # legacy
    networking.useDHCP = lib.mkForce false;
  };
}
