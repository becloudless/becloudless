{
  description = "bcl infra";

  outputs = {self, ...} @ bclInputs: let
    bclSnowfallLib = bclInputs.snowfall-lib.mkLib {
      inputs = bclInputs;
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
          nixos = with bclInputs; [
            sops-nix.nixosModules.sops
            disko.nixosModules.disko
            impermanence.nixosModules.impermanence
            home-manager.nixosModules.home-manager
          ];
        };
        hosts = {
          iso = {
            modules = with bclInputs; [
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

        bclInputs.sops-nix.nixosModules.sops
        bclInputs.disko.nixosModules.disko
        bclInputs.impermanence.nixosModules.impermanence
        bclInputs.home-manager.nixosModules.home-manager
    ];

    mkFlake = flake-and-lib-options @ {
          inputs,
          src,
          snowfall ? {},
          ...
        }: let
          lib = bclInputs.snowfall-lib.mkLib {
            inherit src;
            inputs = bclInputs // inputs;
            snowfall = snowfall // {
              namespace = "my";
            };
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
