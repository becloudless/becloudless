{ config, lib, pkgs, ... }:

{
  config = lib.mkIf (config.bcl.role.name != "") {
    users.mutableUsers = false; # full as code

    home-manager.backupFileExtension = "hm-backup";
    environment.systemPackages = with pkgs; [
      dconf # dconf is required for home-manager to work
    ];

  };
}
