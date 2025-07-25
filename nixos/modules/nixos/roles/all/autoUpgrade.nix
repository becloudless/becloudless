{ config, lib, pkgs, ... }:

{

  config = lib.mkIf (config.bcl.role.name != "") {

    environment.systemPackages = with pkgs; [
      git
      openssl # ssh over tls
    ];

    home-manager.users.root = { lib, pkgs, ... }: {
      home.file.".ssh/config".text = ''
        Host gitea.bcl.io
          IdentityFile /nix/etcbcl/ssh/ssh_host_ed25519_key
          ProxyCommand /bin/sh -c "openssl s_client -servername ssh-%h -connect ssh-%h:443 -quiet -verify_quiet -verify_return_error 2> /dev/null"
      '';

      home.packages = with pkgs; [
        (writeShellScriptBin "nixos-upgrade" ''
          ${config.system.build.nixos-rebuild}/bin/nixos-rebuild \
            switch \
            --no-write-lock-file \
            --refresh \
            --flake ${config.system.autoUpgrade.flake} \
            --upgrade
        '')
      ];
      home.stateVersion = "23.11";
    };

    system.autoUpgrade = {
      enable = true;
      operation = "boot";
      flake = "'git+ssh://git@gitea.bcl.io/bcl/infra?ref=main&dir=nixos#${config.networking.hostName}'";
      flags = [ "--refresh" "--no-write-lock-file" ];
      randomizedDelaySec = "72h";
      dates = "weekly";
    };

  };
}
