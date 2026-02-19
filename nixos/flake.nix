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
      outputs-builder = channels: {
        packages = {
          # this package must be declared out of snowfall because it refuse to go outside nixos/ folder
          becloudless = let
            pkgs = channels.nixpkgs;
            # Map Nix system to Go platform (GOOS-GOARCH format)
            goPlatform = {
              "x86_64-linux" = "linux-amd64";
              "aarch64-linux" = "linux-arm64";
              "i686-linux" = "linux-386";
              "x86_64-darwin" = "darwin-amd64";
              "aarch64-darwin" = "darwin-arm64";
            }.${pkgs.stdenv.hostPlatform.system} or "linux-amd64";
          in pkgs.buildGo125Module {
            pname = "becloudless";
            version = "0.0.1"; # TODO set the version
            src = ../.;
            vendorHash = "sha256-MZ3ocRax0ZAYp89r0I+fZfdzpwzqtGmdjk7cIl436Ao=";

            nativeBuildInputs = [ pkgs.git ];

            preBuild = ''
              echo "Pre build"
              ./gomake build -p
            '';

            buildPhase = ''
              echo "Build"
              ./gomake build -v "$(./gomake version -H ${revision})"
            '';

            installPhase = ''
              mkdir -p $out/bin
              cp dist/bcl-${goPlatform}/bcl $out/bin/bcl
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
        bclFlake.nixosModules.role
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
            snowfall.namespace = "infra";
          };
          flake-options = builtins.removeAttrs flake-and-lib-options ["inputs" "src"];
        in
          lib.mkFlake (flake-options // {
            systems.modules.nixos = bclModules;
            systems.hosts = {
              install-orangepi5plus = {
                system = "aarch64-linux";
                modules = with bclInputs; [
                  nixos-generators.nixosModules.all-formats
                  ({ lib, ... }: {
                    nixpkgs.pkgs = lib.mkForce (import nixpkgs {
                      localSystem.system = "x86_64-linux";
                      crossSystem.system = "aarch64-linux";
                      overlays = [
                        (final: prev: {
                          bcl = self.packages.${final.stdenv.hostPlatform.system} or {};
                        })
                      ];
                    });
                  })
                ];
              };
              iso = {
                modules = with bclInputs; [
                  "${nixpkgs}/nixos/modules/installer/cd-dvd/installation-cd-minimal.nix"
                  "${nixpkgs}/nixos/modules/installer/cd-dvd/channel.nix"
                  {
                    isoImage.squashfsCompression = "gzip -Xcompression-level 1";
                    isoImage.volumeID = lib.mkForce "bcl-iso";
                    image.baseName = lib.mkForce "bcl";
                  }
                ];
              };
            };

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
