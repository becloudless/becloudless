{
  inputs,
  stdenv,
  ...
}:
stdenv.mkDerivation {
  name = "plymouth-bcl";
  version = "1.0";
  src = ./src;
  buildPhase = ''
    mkdir -p $out/share/plymouth/themes/bcl
    cp $src/* $out/share/plymouth/themes/bcl
  '';
  phases = "buildPhase";
}
