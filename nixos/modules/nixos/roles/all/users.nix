{ config, lib, ... }:

{
  config = lib.mkIf config.bcl.role.enable {
    users.mutableUsers = false;

    # TODO still needed?
    programs.fuse.userAllowOther = true; # required for impermanance of folder

  };
}
