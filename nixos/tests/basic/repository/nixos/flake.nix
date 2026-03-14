{
  inputs = {
    bcl.url = "path:../../../../";
  };

  outputs = inputs: inputs.bcl.mkFlake {
    inherit inputs;
    src = ./.;
  };
}
