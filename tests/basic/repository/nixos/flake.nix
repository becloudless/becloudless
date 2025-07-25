{
  inputs = {
    bcl.url = "path:../../../../nixos";
  };

  outputs = inputs: inputs.bcl.mkFlake {
    inherit inputs;
    src = ./.;
  };
}
