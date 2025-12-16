{ config, lib, ... }:

{
  config = lib.mkIf (config.bcl.role.name != "") {
    users.mutableUsers = false; # full as code

    # TODO still needed?
    programs.fuse.userAllowOther = true; # required for impermanance of folder

  };
}
