{
  description = "bcl infra";

  outputs = {self, ...} @ bclInputs: let
    revision = self.rev or "dirty";

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

    # TODO use mkFlake to build bclFlake?
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
      };

      overlays = [
        (final: prev: {
          bcl = (bclFlake.packages.${final.system} or {}); # expose `becloudless` package under `bcl` namespace
        })
      ];
    };


    lib = bclInputs.nixpkgs.lib;

    bclModules = [
        bclFlake.nixosModules.global
        bclFlake.nixosModules.group
        bclFlake.nixosModules."parts/wm"
        bclFlake.nixosModules.role
        bclFlake.nixosModules.system

        bclInputs.nixos-facter-modules.nixosModules.facter
        bclInputs.sops-nix.nixosModules.sops
        bclInputs.disko.nixosModules.disko
        bclInputs.impermanence.nixosModules.impermanence
        bclInputs.home-manager.nixosModules.home-manager
        bclInputs.nixos-generators.nixosModules.all-formats # allow any system to be generated as iso, raw-efi, etc.
    ];

    mkFlake = flake-and-lib-options @ {
          inputs,
          src,
          ...
        }: let
          lib = bclInputs.snowfall-lib.mkLib {
            inherit src;
            inputs = bclInputs // inputs;
            snowfall.namespace = "infra";
          };
          flake-options = builtins.removeAttrs flake-and-lib-options ["inputs" "src"];
        in
          lib.mkFlake (flake-options // {
            systems.modules.nixos = bclModules;

            # Ensure downstream flakes see the bcl package namespace under pkgs.bcl
            overlays = [
              (final: prev: {
                bcl = self.packages.${final.stdenv.hostPlatform.system} or {};
              })
            ];

          });
  in
    bclFlake // {
      inherit mkFlake;
    };

  #################################

  inputs = {
    nixpkgs = {
      url = "github:NixOS/nixpkgs/nixos-25.11";
    };

    nixpkgs-unstable = {
      url = "github:nixos/nixpkgs/nixpkgs-unstable";
    };

    snowfall-lib = {
      url = "github:snowfallorg/lib";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixos-facter-modules = {
      url = "github:nix-community/nixos-facter-modules";
    };

    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    home-manager = {
      url = "github:nix-community/home-manager/release-25.11";
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
