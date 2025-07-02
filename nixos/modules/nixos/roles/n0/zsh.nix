{ config, lib, pkgs, ... }: {
  config = lib.mkIf (config.bcl.role.name == "n0") {

    programs.zsh = {
      enable = true;
      enableCompletion = true;
      enableBashCompletion = true;
      autosuggestions.enable = true;
  #    autosuggestions.highlightStyle = "fg=yellow";

      syntaxHighlighting.enable = true;
    };
  #  users.defaultUserShell = pkgs.zsh;
  # environment = {
  #    shells = [ pkgs.bashInteractive pkgs.zsh ];
  #  };

    users.users.n0rad = {
      shell = pkgs.zsh;
    };

    home-manager.users.n0rad = { lib, pkgs, ... }: {

      programs.zsh = {
        enable = true;
        initExtra = ''
            source ${pkgs.grc}/etc/grc.zsh
            source <(thefuck --alias)

            for i in ~/.zshrc.d/*.zsh; do
              . $i
            done
            for i in ~/.zshrc.d2/*.zsh; do
              . $i
            done
          '';
      };
      programs.zoxide.enable = true;
  #    # https://github.com/nix-community/home-manager/blob/master/modules/programs/z-lua.nix
  #    # https://nix-community.github.io/home-manager/options.xhtml#opt-programs.z-lua.enable
  #    programs.z-lua = {
  #      enable = true;
  #      enableAliases = true;
  #      enableBashIntegration = true;
  #      enableZshIntegration = true;
  #      options =[
  #        "enhanced"
  #        "once"
  #      ];
  #    };

    };
  };
}