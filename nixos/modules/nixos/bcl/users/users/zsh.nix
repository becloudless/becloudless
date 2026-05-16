{ config, lib, pkgs, ... }:

let
  cfg = config.bcl.users.users;
  zshUsers = lib.filterAttrs (_: u: u.shell == "zsh") cfg;
in
{
  config = lib.mkIf (zshUsers != {}) {
    programs.zsh = {
      enable = true;
      enableCompletion = true;
      enableBashCompletion = true;
      autosuggestions.enable = true;
      syntaxHighlighting.enable = true;
    };

    users.users = lib.mapAttrs (_: _: {
      shell = pkgs.zsh;
    }) zshUsers;

    home-manager.users = lib.mapAttrs (_: _: { lib, pkgs, ... }: {
      programs.zsh = {
        enable = true;
        initContent = ''
          source ${pkgs.grc}/etc/grc.zsh
          source <(pay-respects zsh --alias)

          for i in ~/.zshrc.d/*.zsh; do
            . $i
          done
          for i in ~/.zshrc.d2/*.zsh; do
            . $i
          done
        '';
      };
      programs.zoxide.enable = true;
    }) zshUsers;
  };
}
