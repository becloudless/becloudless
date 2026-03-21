{ config, lib, pkgs, ... }:

let
  cfg = config.bcl.syncthing;

  enabledUsers = lib.filterAttrs (_: u: u.syncthing.enable) config.bcl.users;

  mkUserConfig = userName: userCfg:
    let
      st = userCfg.syncthing;
    in {
    sops.secrets."syncthing.${config.networking.hostName}.${userName}.cert" = {
      owner = userName;
      sopsFile = userCfg.sopsFile;
      path = "/nix/syncthing/${userName}/config/cert.pem";
    };
    sops.secrets."syncthing.${config.networking.hostName}.${userName}.key" = {
      owner = userName;
      sopsFile = userCfg.sopsFile;
      path = "/nix/syncthing/${userName}/config/key.pem";
    };

    systemd.tmpfiles.rules = [
      "d /nix/syncthing/${userName}/config 0700 ${userName} users"
    ];

    systemd.services."syncthing-${userName}" = {
      description = "Syncthing for ${userName}";
      after = [ "network.target" "sops-nix.service" ];
      wantedBy = [ "multi-user.target" ];
      environment = {
        STNODEFAULTFOLDER = "true";
      };
      serviceConfig = {
        User = userName;
        ExecStart = lib.concatStringsSep " " [
          "${pkgs.syncthing}/bin/syncthing serve"
          "--no-browser"
          "--no-restart"
          "--logflags=0"
          "--config=/nix/syncthing/${userName}/config"
          "--data=/nix/syncthing/${userName}/home"
        ];
        Restart = "on-failure";
        SuccessExitStatus = "3 4";
        RestartForceExitStatus = "3 4";
        PrivateTmp = true;
        ProtectSystem = "full";
        ReadWritePaths = [
          "/nix/syncthing/${userName}"
        ];
      };
    };

    environment.persistence."/nix/syncthing/${userName}" = {
      hideMounts = true;
      users."${userName}".directories = lib.attrNames st.folders;
    };

    environment.persistence."/nix/syncthing/homes" = {
      hideMounts = true;
      users."${userName}" = {
        directories = [ ".mozilla" ];
        files = [ ".z" ];
      };
    };
  };
in
{
  options.bcl.syncthing = {
    enable = lib.mkEnableOption "Enable";
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge (lib.mapAttrsToList mkUserConfig enabledUsers)
  );
}
