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
    users.users.tv.linger = true;

    systemd.services.greetd = {
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
    };

    services.greetd = {
      enable = true;
      settings.default_session = {
        command = let
          jellyfinSettings = pkgs.writeText "jellyfin-desktop-settings.json" (builtins.toJSON {
            serverUrl = config.bcl.role.tv.jellyfinUrl;
            windowMaximized = true;
            windowDecorations = "csd";
          });
          labwcRc = pkgs.writeText "labwc-rc.xml" ''
            <?xml version="1.0"?>
            <labwc_config>
              <core>
                <decoration>none</decoration>
              </core>
              <windowRules>
                <windowRule title="*">
                  <action name="Fullscreen"/>
                </windowRule>
              </windowRules>
            </labwc_config>
          '';
          jellyfinScript = pkgs.writeShellScript "start-jellyfin" ''
            echo "=== jellyfin startup ===" >> /tmp/tv-startup.log
            rm -f ~/.cache/jellyfin-desktop/SingletonLock ~/.cache/jellyfin-desktop/SingletonCookie
            randr_out=$(${pkgs.wlr-randr}/bin/wlr-randr 2>/dev/null) || true
            output=$(echo "$randr_out" | grep -m1 '^[A-Za-z]' | awk '{print $1}')
            resolution=$(echo "$randr_out" | grep -m1 'current' | awk '{print $1}')
            # Only switch to 23.976 if both the output and mode are actually available (TODO: https://github.com/jellyfin/jellyfin-desktop/issues/247)
            if [ -n "$output" ] && [ -n "$resolution" ] && echo "$randr_out" | grep -q "$resolution.*23\.97"; then
              ${pkgs.wlr-randr}/bin/wlr-randr --output "$output" --mode "$resolution"@23.976 || true
            fi
            jellyfin-desktop
          '';
          startScript = pkgs.writeShellScript "start-labwc" ''
            mkdir -p ~/.config/jellyfin-desktop ~/.config/labwc
            cp ${jellyfinSettings} ~/.config/jellyfin-desktop/settings.json
            cp ${labwcRc} ~/.config/labwc/rc.xml
            echo "=== rc.xml ===" > /tmp/tv-startup.log
            cat ~/.config/labwc/rc.xml >> /tmp/tv-startup.log
            echo "=== labwc start ===" >> /tmp/tv-startup.log
            exec ${pkgs.labwc}/bin/labwc -d -s ${jellyfinScript} >> /tmp/tv-startup.log 2>&1
          '';
        in "${startScript}";
        user = "tv";
      };
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
