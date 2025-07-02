{ config, lib, pkgs, ... }:

{
  config = lib.mkIf (config.bcl.role.name == "game") {
    bcl.sound.enable = true;


    security.sudo.wheelNeedsPassword = false;

    users.users.player = {
      isNormalUser = true;
      description = "player";
      extraGroups = [ "wheel" ];
      password = "qw";
      openssh.authorizedKeys.keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILvM8t4hXJxjBzrUS5FhAQ/TD9TJscT7CyLKFSOjZjj4 id_ed25519"
      ];
    };

    nixpkgs.config.allowUnfreePredicate = pkg: builtins.elem (lib.getName pkg) [
      "steam"
      "steam-original"
      "steam-run"
      "nvidia-x11"
      "nvidia-settings"
    ];

    programs.firefox = {
      enable = true;
    };

    environment.systemPackages = with pkgs; [
      btrfs-progs
      gptfdisk hdparm mdadm dosfstools smartmontools
      pciutils usbutils
      ethtool conntrack-tools iputils iproute2
      htop iftop lsof dfc psmisc ncdu tree nmon
      s-tui stress
      gdb
      wakeonlan

      breeze-plymouth nixos-bgrt-plymouth
      cryptsetup sops
      vim
      wget
      ungoogled-chromium
      gnome-browser-connector gnome.gnome-tweaks gnome.dconf-editor
      kitty tdrop alacritty guake
      # obsidian
      # cinnamon.mint-x-icons
      cinnamon.nemo
      wavemon powertop
      ranger
      # syncthingtray
      tmux tmux-cssh xsel
      gitFull meld git-trim
      grc # pygmentize
      bc yq jq ipcalc
      sshfs
      mplayer mpv vlc ffmpeg x264 x265 flac
      # quicktile-git
      # oh-my-zsh-git
      wineWowPackages.stable winetricks
      # dxvk-bin
      gnupg libsecret # x11_ssh_askpass

      powerline-go thefuck

      lutris
    ];


    networking.firewall.enable = false;

    services.xserver.displayManager.gdm.enable = true;
    services.xserver.desktopManager.gnome.enable = true;
    services.xserver = {
      enable = true;
      xkb.layout = "us";
    };


    services.xserver.videoDrivers = ["nvidia"];

    hardware.nvidia = {
      modesetting.enable = true;
      nvidiaSettings = true;
      package = config.boot.kernelPackages.nvidiaPackages.stable;
    };

    programs.steam = {
      enable = true;
      dedicatedServer.openFirewall = true; # Open ports in the firewall for Source Dedicated Server
      localNetworkGameTransfers.openFirewall = true; # Open ports in the firewall for Steam Local Network Game Transfers
      package = pkgs.steam.override {
        extraLibraries = p: with p; [
          (lib.getLib networkmanager)
        ];
      };
    };


  };
}
