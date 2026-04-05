{ config, lib, ... }:
{
  config = lib.mkIf (config.bcl.role.name != "") {
    xdg.mime.defaultApplications = {
      "x-scheme-handler/http"= "firefox.desktop";
      "x-scheme-handler/https"= "firefox.desktop";
    };
  };
}
