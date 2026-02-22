{
  inputs = {
    bcl.url = "github:becloudless/becloudless?ref=main&dir=nixos";
  };

  outputs = inputs: inputs.bcl.mkFlake {
    inherit inputs;
    src = ./.;
  };
}
