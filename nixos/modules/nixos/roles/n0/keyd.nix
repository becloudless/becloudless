{ config, pkgs, lib, ... }:

{
  config = lib.mkIf (config.bcl.role.name == "n0") {
    services.keyd = {
      enable = true;
      keyboards = {
        default = {
          ids = ["*"];
          settings = {
            # thinkpad fn+up/down is not mappable. getting around with global other schema
            # "control+alt+meta" = {
            "control+meta" = {
              left = "home";
              right = "end";
              up = "pageup";
              down = "pagedown";
            };
          };
        };
      };
    };
  };
}
