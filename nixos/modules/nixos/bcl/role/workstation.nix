{ config, lib, pkgs, ... }:

let
  cfg = config.bcl.role;
in
{
  options.bcl.role.workstation = { };

  config = lib.mkMerge [
    { bcl.role.knownRoles = [ "workstation" ]; }
    (lib.mkIf (config.bcl.role.name == "workstation") {
    bcl.diskSystem.encrypted = true;
    bcl.boot.plymouth.enable = true;
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
      libreoffice 
      # nemo
      # turbovnc

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
      finamp jellyfin-desktop ffmpeg x264 x265 flac
      # mplayer mpv vlc
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

      # Electron apps read GTK3 settings.ini directly and ignore dconf color-scheme.
      # Override the desktop entry to force the dark variant only for jellyfin-desktop.
      xdg.desktopEntries.jellyfin-desktop = {
        name = "Jellyfin Desktop";
        exec = "env GTK_THEME=Adwaita:dark jellyfin-desktop %U";
        icon = "jellyfin-desktop";
       comment = "Jellyfin Desktop Client";
        categories = [ "AudioVideo" "Video" "Player" ];
      };


    services.xserver = {
      enable = true;
    };

  })
  ];
}
