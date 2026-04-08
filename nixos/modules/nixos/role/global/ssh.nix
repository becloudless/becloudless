{ config, lib, ... }:

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
        ProxyCommand /bin/sh -c "openssl s_client -servername ssh-%h -connect ssh-%h:443 -quiet -verify_quiet -verify_return_error 2> /dev/null"
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
