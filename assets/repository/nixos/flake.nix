{
  outputs = {self, ...} @ inputs: let
    lib = inputs.bcl.inputs.snowfall-lib.mkLib {
      inputs = inputs.bcl.inputs // inputs;
      src = ./.;
      snowfall.namespace = "my";
    };

    flake = lib.mkFlake {
      systems.modules.nixos = lib.toList inputs.bcl.nixosModules.system;
    };

  in flake // inputs.bcl.outputs;

  #################################

  inputs = {
    bcl = {
      url = "github:becloudless/becloudless?ref=n0/init&dir=nixos";
    };
  };
}
