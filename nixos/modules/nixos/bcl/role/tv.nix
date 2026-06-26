{ inputs, config, lib, pkgs, ... }:
{

  imports = [
    "${inputs.nix-flatpak}/modules/nixos.nix"
  ];

  options.bcl.role.tv = {
    audioType = lib.mkOption {
         type = lib.types.str;
         default = "basic";
      };
    audioDevice = lib.mkOption {
         type = lib.types.str;
         default = "auto";
      };
    jellyfinUrl = lib.mkOption {
         type = lib.types.str;
         default = "https://jellyfin.${config.bcl.global.domain}";
      };
  };

  config = lib.mkMerge [
    { bcl.role.knownRoles = [ "tv" ]; }
    (lib.mkIf (config.bcl.role.name == "tv") {
    bcl.boot.quiet = true;
    bcl.sound.enable = true;
    bcl.wifi.enable = true;

    bcl.users.users.tv = {};

    services.greetd = {
      enable = true;
      settings.default_session = {
        command =
          let
            dwmSession = pkgs.writeShellScript "dwm-session" ''
              ${pkgs.xorg.xsetroot}/bin/xsetroot -solid black
              ${pkgs.xorg.xset}/bin/xset -dpms
              ${pkgs.xorg.xset}/bin/xset s off
              while true; do
                ${pkgs.bcl.jellyfin-desktop}/bin/jellyfin-desktop
                sleep 5
              done &
              exec ${pkgs.dwm}/bin/dwm
            '';
          in
          "${pkgs.xorg.xinit}/bin/startx ${dwmSession} -- :0 vt1";
        user = "tv";
      };
    };

    services.speechd.enable = false; # remove mbrola-voices dependency that is huge
    security.sudo.wheelNeedsPassword = false;

    services.xserver.enable = true;

    environment.systemPackages = with pkgs; [
      dwm
      pulseaudio
      bcl.jellyfin-desktop
      xorg.xinit
      xorg.xsetroot
      xorg.xset
    ];

    systemd.tmpfiles.rules = [
      "d /nix/home/tv 0700 tv users"
    ];

    environment.persistence."/nix" = {
      users."tv".directories = [
        ".config/jellyfin-desktop"
      ];
    };

  })
  ];
}