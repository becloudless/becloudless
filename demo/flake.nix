{
  description = "BCL demo";

  outputs = {bcl, ...} @ inputs: let
    lib = bcl.inputs.snowfall-lib.mkLib {
      inputs = bcl.inputs;
      src = ./.;

      snowfall = {
        meta = {
          name = "bcl";
          title = "BCL Config";
        };
        namespace = "bcl";
      };
    };
  in
    lib.mkFlake {
      systems = {
        modules = {
          nixos = with inputs; [
            sops-nix.nixosModules.sops
            disko.nixosModules.disko
            impermanence.nixosModules.impermanence
            home-manager.nixosModules.home-manager
          ];
        };
      };
    };

  #################################

  inputs = {
    bcl.url = "path:..";
  };
}
