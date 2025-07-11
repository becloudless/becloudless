{
  description = "bcl infra";

  outputs = {self, ...} @ inputs: let
    bclSnowfallLib = inputs.snowfall-lib.mkLib {
      inherit inputs;
      src = ./.;

      snowfall = {
        meta = {
          name = "bcl";
          title = "bcl Config";
        };
        namespace = "bcl";
      };
    };

    bclFlake = bclSnowfallLib.mkFlake {
      systems = {
        modules = {
          nixos = with inputs; [
            sops-nix.nixosModules.sops
            disko.nixosModules.disko
            impermanence.nixosModules.impermanence
            home-manager.nixosModules.home-manager
          ];
        };
        hosts = {
          iso = {
            modules = with inputs; [
              "${nixpkgs}/nixos/modules/installer/cd-dvd/installation-cd-minimal.nix"
              "${nixpkgs}/nixos/modules/installer/cd-dvd/channel.nix"
            ];
          };
        };
      };
    };


    bclModules = [
        bclFlake.nixosModules.global
        bclFlake.nixosModules.system
        bclFlake.nixosModules.roles
        bclFlake.nixosModules."parts/wm"
        bclFlake.nixosModules.hardware

        inputs.sops-nix.nixosModules.sops
        inputs.disko.nixosModules.disko
        inputs.impermanence.nixosModules.impermanence
        inputs.home-manager.nixosModules.home-manager
    ];


    mkLib = inputs.snowfall-lib.mkLib;
    mkFlake = flake-and-lib-options @ {
          inputs,
          src,
          ...
        }: let
          lib = mkLib {
            inherit inputs src;
            snowfall.namespace = "my";
            systems.modules.nixos = bclModules;
          };
          flake-options = builtins.removeAttrs flake-and-lib-options ["inputs" "src"];
        in
          lib.mkFlake flake-options;
  in
    bclFlake // {
      inherit mkFlake bclModules;
    };

  #################################

  inputs = {
    nixpkgs = {
      url = "github:NixOS/nixpkgs/nixos-24.11";
    };

    snowfall-lib = {
      url = "github:snowfallorg/lib";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    home-manager = {
      url = "github:nix-community/home-manager/release-24.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    impermanence = {
      url = "github:nix-community/impermanence";
    };

    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixos-generators = {
      url = "github:nix-community/nixos-generators";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    yaml = {
      url = "github:jim3692/yaml.nix";
    };
  };
}
