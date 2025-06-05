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

    # hardware.printers = {
    #   ensurePrinters = [
    #     {
    #       name = "ip2700";
    #       location = "Home";
    #       deviceUri = "usb://Canon/iP2700%20series?serial=F8241F";
    #       model = "gutenprint.${lib.versions.majorMinor (lib.getVersion pkgs.gutenprint)}://brother-hl-5140/expert";
    #       ppdOptions = {
    #         PageSize = "A4";
    #       };
    #     }
    #   ];
    #   ensureDefaultPrinter = "ip2700";
    # };

    hardware.sane.enable = true;
    environment.systemPackages = with pkgs; [
  #    sane
  #    xsane
      pdftk
      tesseract
    ];
  };
}
