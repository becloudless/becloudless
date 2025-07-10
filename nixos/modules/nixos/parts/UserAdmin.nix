{ config, lib, ... }:

{
  config = lib.mkIf config.bcl.role.enable {

#    sops.secrets."users.n0rad.password" = lib.mkIf config.bcl.role.setN0radPassword {
#      neededForUsers = true;  # sops hook in the init process before creation of users
#      sopsFile = ../../secrets.yaml;
#    };

    services.displayManager.hiddenUsers = [ "n0rad" ];

    users.users.n0rad = {
      isNormalUser = true;
      description = "n0rad";
      group = "users";
      extraGroups = [ "wheel" ];
#      hashedPasswordFile = lib.mkIf config.bcl.role.setN0radPassword config.sops.secrets."users.n0rad.password".path;
      openssh.authorizedKeys.keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILvM8t4hXJxjBzrUS5FhAQ/TD9TJscT7CyLKFSOjZjj4 id_ed25519"
      ];
    };

    home-manager.users.n0rad = { lib, pkgs, ... }: {
      home.stateVersion = "23.11";
    };
  };
}
