{ config, lib, pkgs, ... }: {

  bcl = {
    global = {
      enable = true;
    };
#    role = {
#      enable = true;
#      name = "install";
#    };
  };


  services.getty.helpLine = lib.mkForce ">> Run lmr-install to install";
  # give time to dhcp to get IP, so it will be display
  services.getty.extraArgs = [ "--delay=5" ];
  environment.etc."issue.d/ip.issue".text = "\\4\n";
  networking.dhcpcd.runHook = "${pkgs.utillinux}/bin/agetty --reload";

  # faster compression
  isoImage.squashfsCompression = "gzip -Xcompression-level 1";

  isoImage.volumeID = lib.mkForce "bcl-iso";
  isoImage.isoName = lib.mkForce "bcl.iso";
}
