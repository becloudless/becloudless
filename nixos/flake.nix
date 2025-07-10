{
  description = "bcl infra";

  outputs = {self, ...} @ inputs: let
    lib = inputs.snowfall-lib.mkLib {
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

    flake = lib.mkFlake {
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
  in
    flake // {
      bclModules = [
        flake.nixosModules.global
        flake.nixosModules.system
        flake.nixosModules.roles
        flake.nixosModules."parts/wm"
        flake.nixosModules.hardware

        inputs.sops-nix.nixosModules.sops
        inputs.disko.nixosModules.disko
        inputs.impermanence.nixosModules.impermanence
        inputs.home-manager.nixosModules.home-manager
      ];
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
