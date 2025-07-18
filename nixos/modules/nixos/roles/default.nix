{ config, lib, pkgs, inputs, ... }:
let
  cfg = config.bcl.role;
  revision = let self = inputs.self; in self.shortRev or self.dirtyShortRev or self.lastModified or "unknown";
in {

  options.bcl.role = {
    enable = lib.mkEnableOption "Enable";
    name = lib.mkOption {
      type = lib.types.str;
      default = "";
    };
    setN0radPassword = lib.mkEnableOption "Set password";
  };

  config = lib.mkIf cfg.enable {
    system.nixos.tags = ["role-${cfg.name}"];
    system.nixos.versionSuffix = "-${builtins.substring 0 8 (toString inputs.self.lastModifiedDate)}.${revision}";
    # system.nixos.label =

    environment.etc."nixos/current".source = inputs.self.outPath;

    system.stateVersion = "23.11"; # never touch that
  };
}
