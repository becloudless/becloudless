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
      outputs-builder = channels: {
        packages = {
          becloudless = channels.nixpkgs.buildGo124Module {
            pname = "becloudless";
            version = "0.0.1";
            src = ../.;
            vendorHash = "sha256-/BhJK7RrBYQyw70buf6vP5fCIq6aUk2uyCq+lBYElLQ=";

            nativeBuildInputs = [ channels.nixpkgs.pkgs.git ];

            preBuild = ''
              echo "Pre build"
              mkdir -p dist-tools
              go build -o ./dist-tools/go-jsonschema github.com/atombender/go-jsonschema
              go generate ./...
            '';

            # TODO this results with a fake version suffix
            buildPhase = ''
              echo "Build"
              export HOME=$PWD
              git config --global user.email "you@example.com"
              git config --global user.name "Your Name"
              git config --global init.defaultBranch main
              git init .
              git add .
              git commit -m "init" || true

              ./gomake build
            '';

            installPhase = ''
              mkdir -p $out/bin
              cp dist/bcl-linux-amd64/bcl $out/bin/bcl
            '';
          };
        };
      };

      overlays = [
        (final: prev: {
          bcl = (bclFlake.packages.${final.system} or {}); # expose `becloudless` package under `bcl` namespace
        })
      ];
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
                bcl = self.packages.${final.system} or {};
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
      url = "github:NixOS/nixpkgs/nixos-25.11";
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
