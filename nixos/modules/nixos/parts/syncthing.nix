{ config, lib, pkgs, ... }:

let
  cfg = config.bcl.syncthing;
in
{
  options.bcl.syncthing = {
    enable = lib.mkEnableOption "Enable";
    user = lib.mkOption { type = lib.types.str; };
    sopsFile = lib.mkOption { type = lib.types.path;};
    remote = lib.mkOption {
     type = (lib.types.submodule {
       options = {
         id = lib.mkOption { type = lib.types.str; };
       };
     });
    };
    homeFolderId = lib.mkOption {
      type = lib.types.str;
      default = "";
    };
    folders = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule {
        options = {
          id = lib.mkOption { type = lib.types.str; };
          key = lib.mkOption { type = lib.types.str; };
          endpoint = lib.mkOption { type = lib.types.str; };
        };
      });
    };
  };

  config = lib.mkIf cfg.enable {
    sops.secrets."syncthing.${config.networking.hostName}.cert" = {
      owner = cfg.user;
      sopsFile = cfg.sopsFile;
      path = "/nix/syncthing/config/cert.pem";
    };
    sops.secrets."syncthing.${config.networking.hostName}.key" = {
      owner = cfg.user;
      sopsFile = cfg.sopsFile;
      path = "/nix/syncthing/config/key.pem";
    };

    systemd.tmpfiles.rules = [
      "d /nix/syncthing/config 0700 ${cfg.user} users"
    ] ;

    services.syncthing = {
      enable = true;
      user = cfg.user;
      relay.enable = false;
      dataDir = "/nix/syncthing/home/${cfg.user}"; # used only as default for new folder sync
      configDir = "/nix/syncthing/config";
      settings = {
        options = {
          localAnnounceEnabled = false;
          relaysEnabled = true;
          urAccepted = -1;
          listenAddresses = [
            "relay://syncthing.bcl.io:22067/?id=??"
          ];
        };
#      gui =
        devices = {
          "${cfg.user}.syncthing.bcl.io" = {
            id = cfg.remote.id;
            autoAcceptFolders = false;
          };
        };
        folders = lib.mergeAttrs (lib.mapAttrs' (k: v: lib.nameValuePair k {
          id = v.id;
          path = "/nix/syncthing/home/${cfg.user}/${k}";
          devices = [ "${cfg.user}.syncthing.bcl.io" ];
        }) cfg.folders) (if cfg.homeFolderId != "" then {
          "Home" = {
            id = cfg.homeFolderId;
            path = "/nix/syncthing/homes/home/${cfg.user}";
            devices = [ "${cfg.user}.syncthing.bcl.io" ];
            fsWatcherEnabled = false;
            rescanIntervalS = 3600; # 1h
          };
        } else {});
      };
    };


    environment.persistence."/nix/syncthing" = {
      hideMounts = true;
      users."${cfg.user}".directories = (lib.attrNames cfg.folders);
    };

    environment.persistence."/nix/syncthing/homes" = {
      hideMounts = true;
      users."${cfg.user}" = {
        directories = [
          ".mozilla"
        ];
        files = [
          ".z"
        ];
      };
    };

    systemd.services.syncthing.environment.STNODEFAULTFOLDER = "true"; # Don't create default ~/Sync folder

  };
}
