{ config, lib, pkgs, ... }:
let
  cfg = config.bcl.printScan;
in
{
  options.bcl.printScan.enable = lib.mkEnableOption "Enable";

  config = lib.mkIf cfg.enable {

    services.printing.enable = true;
    services.printing.drivers = with pkgs; [
      gutenprint
    ];

    hardware.sane.enable = true;
    environment.systemPackages = with pkgs; [
  #    sane
  #    xsane
      pdftk
      tesseract
    ];
  };
}
