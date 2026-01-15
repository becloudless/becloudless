{ config, lib, ... }:

{
  config = lib.mkIf (config.bcl.role.name != "") {
    users.mutableUsers = false; # full as code
  };
}
