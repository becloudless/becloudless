{ lib, config, ... }:
let
  bindsCfg = config.bcl.dataBinds;
  mkBindData = from: to: {
    name = "/data/${to}";
    value = {
      device = from;
      fsType = "none";
      options = ["bind" "noauto"];
    };
  };
in {
  options.bcl.dataBinds = lib.mkOption {
    type = lib.types.attrsOf lib.types.str;
    example = {
      scratch = "/disks/nvme1/scratch";
    };
    description = "Bind mount definitions mapping name -> source path. Each creates /data/{name} bound to the source path. Activated only when data disks are defined.";
  };

  config = lib.mkIf (bindsCfg != {}) {
    systemd.services."mount-data-binds" = {
      enable = true;
      script = lib.concatStringsSep "\n" (
        lib.mapAttrsToList (to: _: "systemctl start data-${to}.mount") bindsCfg
      );
      after = [ "fs-local.target" ];
      wantedBy = ["multi-user.target"];
    };

    fileSystems = builtins.listToAttrs (lib.mapAttrsToList (to: from: mkBindData from to) bindsCfg);
  };
}

