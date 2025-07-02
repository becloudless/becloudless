{ config, lib, ... }:

{
  config = lib.mkIf config.bcl.role.enable {
    time.timeZone = "Europe/Paris";

    i18n.defaultLocale = "en_US.UTF-8";
  };
}
