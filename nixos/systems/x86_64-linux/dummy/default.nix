{ pkgs, ... }:
{
  boot.loader.grub.devices = [ "/dev/null" ];
  fileSystems."/".device = "/dev/null";

  # Add becloudless Go binary from the bcl overlay to the system packages
  environment.systemPackages = with pkgs; [
    bcl.becloudless
  ];

}
