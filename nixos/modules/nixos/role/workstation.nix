{ config, lib, pkgs, ... }:

let
  cfg = config.bcl.role.workstation;

  localeMap = {
    en = "en_US.UTF-8";
    fr = "fr_FR.UTF-8";
  };

  locale = localeMap.${cfg.language} or "${cfg.language}";
in
{
  options.bcl.role.workstation = {
    language = lib.mkOption {
      type = lib.types.str;
      default = "en";
      description = "Language for the workstation (e.g. 'en', 'fr').";
    };
    keyboard = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "us" ];
      description = "Keyboard layouts for the workstation (e.g. [ 'us' ] or [ 'fr' 'us' ]). First layout will be used as default.";
    };
  };

  config = lib.mkMerge [
    { bcl.role.knownRoles = [ "workstation" ]; }
    (lib.mkIf (config.bcl.role.name == "workstation") {
    bcl.disk.encrypted = true;
    bcl.boot.plymouth = true;
    bcl.boot.quiet = true;
    bcl.bluetooth.enable = true;
    bcl.sound.enable = true;
    bcl.wifi.enable = true;
    bcl.docker.enable = true;
    bcl.printScan.enable = true;
    bcl.role.setAdminPassword = true;
    bcl.keepassxc.enable = true;

    programs.firefox = {
      enable = true;
    };

    environment.systemPackages = with pkgs; [
      # System
      wavemon powertop htop iftop lsof dfc psmisc ncdu tree nmon
      s-tui stress
      gnupg libsecret sops kubeseal ssh-to-age

      # office
      libreoffice nemo
      ungoogled-chromium
      turbovnc

      # Dev
      gitFull meld git-trim
      vscodium gh graphviz
      kubectl krew kubernetes-helm k9s kubeseal stern fluxcd helm-ls cilium-cli kubelogin-oidc
      istioctl renovate # terraform # terraform-docs
      dgoss gcrane
      go yarn gradle maven nodejs_24

      # Nix
      nixos-anywhere

      # Media
      finamp mplayer mpv vlc ffmpeg x264 x265 flac
      gimp imagemagick ghostscript

      # Shell
      powerline-go pay-respects
      tig tk silver-searcher 
      # quicktile-git
      # oh-my-zsh-git
      tmux tmux-cssh xsel expect
      sshfs gocryptfs
      bc yq-go jq ipcalc dyff
      grc # pygmentize
      ranger
    ];

    services.xserver = {
      enable = true;
      xkb.layout = lib.concatStringsSep "," cfg.keyboard;
    };

    console.keyMap = builtins.head cfg.keyboard;
    i18n.defaultLocale = lib.mkForce locale;

    i18n.extraLocaleSettings = {
      LC_ADDRESS = locale;
      LC_IDENTIFICATION = locale;
      LC_MEASUREMENT = locale;
      LC_MONETARY = locale;
      LC_NAME = locale;
      LC_NUMERIC = locale;
      LC_PAPER = locale;
      LC_TELEPHONE = locale;
      LC_TIME = locale;
    };

  })
  ];
}
