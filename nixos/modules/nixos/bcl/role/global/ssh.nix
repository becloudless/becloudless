{ config, lib, pkgs, ... }:

{
  config = lib.mkIf (config.bcl.role.name != "") {

    services.openssh = {
      enable = true;
      hostKeys = [
        {
          path = "/nix/etc/ssh/ssh_host_ed25519_key";
          type = "ed25519";
        }
      ];
      settings = {
        PasswordAuthentication = false;
        KbdInteractiveAuthentication = false;
      };
    };

    programs.ssh.extraConfig = ''
      Host gitea.${config.bcl.global.domain}
        ProxyCommand ${pkgs.nmap}/bin/ncat --ssl --sni ssh-%h %h 443
    '';

    programs.ssh.knownHosts = {
      "gitea.${config.bcl.global.domain}" = {
        hostNames = [ "gitea.${config.bcl.global.domain}" ];
        publicKey = config.bcl.global.git.publicKey;
      };

      "github.com" = {
        hostNames = [ "github.com" ];
        publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl";
      };
    };
  };
}
