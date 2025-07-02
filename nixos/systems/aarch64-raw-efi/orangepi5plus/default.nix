{
  lib,
  pkgs,
  ...
}:  {
#
  bcl.hardware = {
    device = "orangepi5plus";
  };
#
##  # Reuse and extend the raw-efi format
##  imports = [
##    nixos-generators.nixosModules.raw-efi
##  ];
#
#  boot.loader = {
#    systemd-boot.extraInstallCommands = extraInstallCommands;
#    grub.extraInstallCommands = extraInstallCommands;
#  };


  nix.settings = {
    experimental-features = ["nix-command" "flakes"];
  };

  # List packages installed in system profile. To search, run:
  # $ nix search wget
  environment.systemPackages = with pkgs; [
    git # used by nix flakes
    curl

    neofetch
    lm_sensors # `sensors`
    btop # monitor system resources

    # Peripherals
    mtdutils
    i2c-tools
    minicom
  ];

  # Enable the OpenSSH daemon.
  services.openssh = {
    enable = lib.mkDefault true;
    settings = {
      X11Forwarding = lib.mkDefault true;
      PasswordAuthentication = lib.mkDefault true;
    };
    openFirewall = lib.mkDefault true;
  };

  # =========================================================================
  #      Users & Groups NixOS Configuration
  # =========================================================================

  # TODO Define a user account. Don't forget to update this!
  users.users."rk" = {
    hashedPassword = "$y$j9T$V7M5HzQFBIdfNzVltUxFj/$THE5w.7V7rocWFm06Oh8eFkAKkUFb5u6HVZvXyjekK6";
    isNormalUser = true;
    home = "/home/rk";
    extraGroups = ["users" "wheel"];
  };

  system.stateVersion = "23.11";

}
