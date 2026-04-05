{ config, lib, pkgs, ... }:
{
  options.bcl.keepassxc.enable = lib.mkEnableOption "Enable";

  config = lib.mkIf config.bcl.keepassxc.enable  {

    programs.ssh.startAgent = true;

    services.gnome.gnome-keyring.enable = lib.mkForce false;
    services.gnome.gcr-ssh-agent.enable = false;

    environment.systemPackages = with pkgs; [
      keepassxc
    ];
  };

}