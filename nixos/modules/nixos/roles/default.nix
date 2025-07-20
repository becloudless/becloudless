{ config, lib, pkgs, inputs, ... }:
let
  cfg = config.bcl.role;
  revision = let self = inputs.self; in self.shortRev or self.dirtyShortRev or self.lastModified or "unknown";
in {

  options.bcl.role = {
    name = lib.mkOption {
      type = lib.types.str;
      default = "";
    };
    setAdminPassword = lib.mkEnableOption "Add the password to the user";
  };

  config = lib.mkIf (cfg.name != "") {
    system.nixos.tags = ["role-${cfg.name}"];
    system.nixos.versionSuffix = "-${builtins.substring 0 8 (toString inputs.self.lastModifiedDate)}.${toString revision}";
    # system.nixos.label =

    environment.etc."nixos/current".source = inputs.self.outPath;

    system.stateVersion = "23.11"; # never touch that
  };
}
