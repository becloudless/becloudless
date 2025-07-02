{ config, lib, pkgs, ... }:
{
  config = lib.mkIf (config.bcl.role.name == "n0") {
    programs.ssh.knownHosts = {
      sftp-n0rad = {
        hostNames = [ "[localhost]:2200" ];
        publicKey = "ecdsa-sha2-nistp521 AAAAE2VjZHNhLXNoYTItbmlzdHA1MjEAAAAIbmlzdHA1MjEAAACFBACu7KKUIL/j/WXCXl6pcFArLS30cE3j6QIya1WiysYo9azSiO1ITCJ2fDBzHDdubCarRiPJajxBwj+E31TbbLIr4QHwJ3ZMERE9d72YsnDIP6qa5QHx9JHIDsXd6YOOns22OGLJJqT4UzcYPP91i70TWO1jTv681yShtjR+6Z7ePG25Pg==";
      };
    };
  };
}
# srv initrd ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKzNMkOnKQ5D2LfWvOoavhZ0lau3RvFb879vUSe7TpVh n0rad@n0l2 
