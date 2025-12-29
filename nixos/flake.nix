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

    # Build the Go module at the git repo root (../.. from this flake)
    # and expose it as a package under pkgs.bcl.becloudless
    goPackageForRepoRoot = system: let
      pkgs = bclInputs.nixpkgs.legacyPackages.${system};
    in
      pkgs.buildGoModule {
        pname = "becloudless";
        version = "0.0.1";

        src = pkgs.lib.cleanSource (pkgs.lib.sourceByRegex ../.. [
          "^becloudless(/.*)?$"
          "^go\.mod$"
          "^go\.sum$"
        ]);

        # If the Go module lives in ../../becloudless/, adjust modRoot
        modRoot = "becloudless";

        vendorHash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";

        CGO_ENABLED = 0;
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
      outputs-builder = channels: {
        packages = {
        };
      };
    };


    bclModules = [
        bclFlake.nixosModules.global
        bclFlake.nixosModules.group
        bclFlake.nixosModules."parts/wm"
        bclFlake.nixosModules.roles
        bclFlake.nixosModules.system

        bclInputs.nixos-facter-modules.nixosModules.facter
        bclInputs.sops-nix.nixosModules.sops
        bclInputs.disko.nixosModules.disko
        bclInputs.impermanence.nixosModules.impermanence
        bclInputs.home-manager.nixosModules.home-manager
    ];

    mkFlake = flake-and-lib-options @ {
          inputs,
          src,
          ...
        }: let
          lib = bclInputs.snowfall-lib.mkLib {
            inherit src;
            inputs = bclInputs // inputs;
            snowfall.namespace = "my";
          };
          flake-options = builtins.removeAttrs flake-and-lib-options ["inputs" "src"];
        in
          lib.mkFlake (flake-options // {
            systems.modules.nixos = bclModules;
            systems.hosts = {
              iso = {
                modules = with bclInputs; [
                  "${nixpkgs}/nixos/modules/installer/cd-dvd/installation-cd-minimal.nix"
                  "${nixpkgs}/nixos/modules/installer/cd-dvd/channel.nix"
                ];
              };
            };

            # Ensure downstream flakes see the bcl package namespace under pkgs.bcl
            overlays = [
              (final: prev: {
                bcl = (self.packages.${final.system} or {}) // {
                  becloudless = goPackageForRepoRoot final.system;
                };
              })
            ];

          }); #// {isoConfigurations = bclFlake.isoConfigurations;};
  in
    bclFlake // {
      inherit mkFlake;
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

    nixos-facter-modules = {
      url = "github:nix-community/nixos-facter-modules";
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
