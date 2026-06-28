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
    services.speechd.enable = lib.mkForce false; # remove mbrola-voices dependency that is huge
    security.sudo.wheelNeedsPassword = false;

    bcl.users.users.tv = {};

    services.greetd = {
      enable = true;
      settings.default_session = {
        command = let
          jellyfinScript = pkgs.writeShellScript "start-jellyfin" ''
            # lock contain machine name, cleanup any previous lock files to support renamed system 
            rm -f ~/.cache/jellyfin-desktop/SingletonLock ~/.cache/jellyfin-desktop/SingletonCookie

            randr_out=$(${pkgs.wlr-randr}/bin/wlr-randr 2>/dev/null) || true
            output=$(echo "$randr_out" | grep -m1 '^[A-Za-z]' | awk '{print $1}')
            resolution=$(echo "$randr_out" | grep -m1 'current' | awk '{print $1}')
            width=$(echo "$resolution" | cut -dx -f1)
            height=$(echo "$resolution" | cut -dx -f2)

            # Only switch to 23.976 if both the output and mode are actually available (TODO: https://github.com/jellyfin/jellyfin-desktop/issues/247)
            if [ -n "$output" ] && [ -n "$resolution" ] && echo "$randr_out" | grep -q "$resolution.*23\.97"; then
              ${pkgs.wlr-randr}/bin/wlr-randr --output "$output" --mode "$resolution"@23.976 || true
            fi

            cat > ~/.config/jellyfin-desktop/settings.json <<EOF
            {"serverUrl":"${config.bcl.role.tv.jellyfinUrl}","windowDecorations":"server","windowWidth":''${width:-1920},"windowHeight":''${height:-1080},"windowLogicalWidth":''${width:-1920},"windowLogicalHeight":''${height:-1080}}
            EOF
            export JELLYFIN_DESKTOP_LOG_LEVEL=debug
            export JELLYFIN_DESKTOP_LOG_FILE=~/.config/jellyfin-desktop/jellyfin-desktop.log
            systemctl --user start screensaver.service || true

            # Wait for network before starting jellyfin
            until ${pkgs.networkmanager}/bin/nm-online -q 2>/dev/null; do sleep 2; done
            jellyfin-desktop
          '';
          startScript = "${pkgs.labwc}/bin/labwc -s ${jellyfinScript}";
        in "${startScript}";
        user = "tv";
      };
    };

    home-manager.users.tv = { lib, pkgs, ... }: {
      home.file.".config/labwc/rc.xml".text = ''
        <?xml version="1.0"?>
        <labwc_config>
          <core>
            <decoration>none</decoration>
          </core>
          <windowRules>
            <windowRule title="*">
              <action name="ToggleFullscreen"/>
            </windowRule>
          </windowRules>
        </labwc_config>
      '';
    };

    environment.systemPackages = with pkgs; [
      pulseaudio
      wlr-randr
      labwc
      bcl.jellyfin-desktop
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
