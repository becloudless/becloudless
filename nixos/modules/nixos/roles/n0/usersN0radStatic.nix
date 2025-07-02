{ config, lib, pkgs, ... }: {
  config = lib.mkIf (config.bcl.role.name == "n0") {
    home-manager.users.n0rad = { lib, pkgs, ... }: {
      # https://github.com/nix-community/home-manager/issues/3849
      home.file."fake/.." = {
          source = ./static-n0rad;
          recursive = true;
      };
    };

    sops.secrets."users.n0rad.zsh.systemdb" = {
     owner = "n0rad";
     sopsFile = ../n0.secrets.yaml;
     path = "/home/n0rad/.zshrc.d2/systemdb.zsh";
    };
  };
}
