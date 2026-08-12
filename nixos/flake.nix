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
            proxmox-nixos.nixosModules.proxmox-ve
          ];
        };
      };

      overlays = [
        (final: prev: {
          bcl = (bclFlake.packages.${final.stdenv.hostPlatform.system} or {}); # expose `becloudless` package under `bcl` namespace
        })
        (final: prev: bclInputs.proxmox-nixos.overlays.${prev.stdenv.hostPlatform.system} final prev)
      ];
    };


    lib = bclInputs.nixpkgs.lib;

    bclModules = [
        bclFlake.nixosModules.bcl

        bclInputs.nixos-facter-modules.nixosModules.facter
        bclInputs.sops-nix.nixosModules.sops
        bclInputs.disko.nixosModules.disko
        bclInputs.impermanence.nixosModules.impermanence
        bclInputs.home-manager.nixosModules.home-manager
        bclInputs.nixos-generators.nixosModules.all-formats # allow any system to be generated as iso, raw-efi, etc.
        bclInputs.proxmox-nixos.nixosModules.proxmox-ve
    ];

    mkFlake = flake-and-lib-options @ {
          inputs,
          src,
          # List of package names (strings) to allow as unfree, e.g. [ "goland" ].
          # Merged with any allowUnfreePredicate already in channels-config.
          allowedUnfreePackages ? [],
          # List of package names (strings) to allow as insecure, e.g. [ "openssl-1.0.2u" ].
          # Merged with any allowInsecurePredicate already in channels-config.
          allowedInsecurePackages ? [],
          snowfall ? {},
          # Map hostname -> alternate bcl flake input (any flake exposing its own
          # `mkFlake`, e.g. another `github:becloudless/becloudless?...&ref=<branch>`
          # input) that host's nixosConfiguration should be built with instead of
          # this flake. Lets a downstream repo pin one or more hosts to a
          # different bcl branch/feature (for testing, staged rollout, etc.)
          # while every other host keeps using this flake as normal. Several
          # hosts can share the same override input.
          bclOverrides ? {},
          ...
        }: let
          lib = bclInputs.snowfall-lib.mkLib {
            inherit src;
            inputs = bclInputs // inputs;
            snowfall = { namespace = "infra"; } // snowfall;
          };
          nixpkgsLib = bclInputs.nixpkgs.lib;
          userChannelsConfig = flake-and-lib-options.channels-config or {};
          unfreeConfig = nixpkgsLib.optionalAttrs (allowedUnfreePackages != []) {
            allowUnfreePredicate = pkg:
              builtins.elem (nixpkgsLib.getName pkg) allowedUnfreePackages
              || (userChannelsConfig.allowUnfreePredicate or (_: false)) pkg;
          };
          insecureConfig = nixpkgsLib.optionalAttrs (allowedInsecurePackages != []) {
            allowInsecurePredicate = pkg:
              builtins.elem (nixpkgsLib.getName pkg) allowedInsecurePackages
              || (userChannelsConfig.allowInsecurePredicate or (_: false)) pkg;
          };
          flake-options = builtins.removeAttrs flake-and-lib-options ["inputs" "src" "allowedUnfreePackages" "allowedInsecurePackages" "snowfall" "bclOverrides"];

          baseFlake = lib.mkFlake (flake-options // {
            systems.modules.nixos = bclModules;

            channels-config = userChannelsConfig // unfreeConfig // insecureConfig;

            # Ensure downstream flakes see the bcl package namespace under pkgs.bcl
            overlays = [
              (final: prev: {
                bcl = self.packages.${final.stdenv.hostPlatform.system} or {};
              })
              (final: prev: bclInputs.proxmox-nixos.overlays.${prev.stdenv.hostPlatform.system} final prev)
            ];

          });

          # Args passed down to each override input's own mkFlake: everything the
          # caller passed to us, minus bclOverrides itself (each override build
          # only needs to produce its own host's nixosConfiguration, not recurse
          # into further overrides).
          overrideFlakeArgs = builtins.removeAttrs flake-and-lib-options ["bclOverrides"];
          overrideFlakes = nixpkgsLib.mapAttrs (host: overrideInput: overrideInput.mkFlake overrideFlakeArgs) bclOverrides;
          overrideConfigurations = nixpkgsLib.mapAttrs (host: flake: flake.nixosConfigurations.${host}) overrideFlakes;

          # flake-utils-plus builds each host's `pkgs` (with overlays applied) by
          # reading `self.pkgs.${system}` at nixosSystem-build time - it does NOT
          # use whichever `mkFlake` call happens to construct a given host's
          # nixosConfiguration. Since `self` is the *whole* (fixpoint) output of
          # this wrapper, overridden hosts would otherwise still resolve to
          # `baseFlake.pkgs` (missing any packages/overlays only added by the
          # override input, e.g. `proxmox-nixos`) even though their
          # nixosConfiguration's modules come from the override's `mkFlake`.
          # Merge each override's per-system `pkgs` in (shallowly, per system) so
          # `self.pkgs` carries the override's overlays too. Note this affects the
          # `pkgs` seen by *every* host on the same system, not just the
          # overridden ones, since `self.pkgs` is shared per-system.
          overridePkgsBySystem = nixpkgsLib.foldl' (acc: flake: acc // (flake.pkgs or {})) {} (builtins.attrValues overrideFlakes);
        in
          baseFlake // {
            pkgs = baseFlake.pkgs // overridePkgsBySystem;
            nixosConfigurations = baseFlake.nixosConfigurations // overrideConfigurations;
          };
  in
    bclFlake // {
      inherit mkFlake;
    };

  #################################

  inputs = {
    fim = {
      url = "github:becloudless/file-integrity-manager";
    };

    nixpkgs = {
      url = "github:NixOS/nixpkgs/nixos-26.05";
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
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    impermanence = {
      url = "github:nix-community/impermanence";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.home-manager.follows = "home-manager";
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
      inputs.nixpkgs.follows = "nixpkgs";
    };

    proxmox-nixos = {
      url = "github:SaumonNet/proxmox-nixos";
    };
  };
}
