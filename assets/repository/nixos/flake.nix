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
      systems.modules.nixos = inputs.bcl.downstreamModules;
    } // inputs.bcl.outputs;

}
