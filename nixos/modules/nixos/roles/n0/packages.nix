{ config, lib, pkgs, ... }:
{
  config = lib.mkIf (config.bcl.role.name == "n0") {

    services.gnome.gnome-browser-connector.enable = true;

    nixpkgs.config.allowUnfreePredicate = pkg: builtins.elem (lib.getName pkg) [
      "goland"
      "yandex-cloud"
    ];

    environment.systemPackages = with pkgs; [
      btrfs-progs
      gptfdisk hdparm mdadm dosfstools smartmontools
      pciutils usbutils
      ethtool conntrack-tools iputils iproute2
      htop iftop lsof dfc psmisc ncdu tree nmon
      s-tui stress
      gdb
      wakeonlan
      libreoffice

      nixos-anywhere
      breeze-plymouth nixos-bgrt-plymouth
      cryptsetup sops kubeseal
      vim
      wget
      ungoogled-chromium
      vscodium jetbrains.goland graphviz
      gnome-browser-connector gnome-tweaks dconf-editor
      kitty tdrop alacritty guake
      yandex-cloud
      # obsidian
      # cinnamon.mint-x-icons
      nemo
      turbovnc
      wavemon powertop
      gimp
      ranger
      # syncthingtray
      tmux tmux-cssh xsel
      kubectl kubernetes-helm k9s kubeseal stern fluxcd helm-ls cilium-cli
      gitFull meld git-trim
      grc # pygmentize
      bc yq-go jq ipcalc dyff
      sshfs gocryptfs
      mplayer mpv vlc ffmpeg x264 x265 flac
      imagemagick ghostscript
      # terraform # terraform-docs
      gcrane
      istioctl
      go yarn gradle maven nodejs_22
      tig tk silver-searcher gh
      # quicktile-git
      # oh-my-zsh-git
      dgoss
      wineWowPackages.stable winetricks
      # dxvk-bin
      gnupg libsecret # x11_ssh_askpass

      powerline-go thefuck
    ];
   };
}
