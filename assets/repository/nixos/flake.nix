{
  inputs = {
    bcl = {
      url = "github:becloudless/becloudless?ref=n0/init&dir=nixos";
    };
  };

  outputs = inputs:
   inputs.bcl.inputs.snowfall-lib.mkFlake {
      inputs = inputs.bcl.inputs // inputs;
      src = ./.;
      snowfall.namespace = "my";
      systems.modules.nixos = inputs.bcl.bclModules;
    };
}
