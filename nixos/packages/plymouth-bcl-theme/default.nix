{
  inputs,
  stdenv,
  ...
}:
stdenv.mkDerivation {
  pname = "plymouth-bcl-theme";
  version = "1.0";
  src = ./src;
  dontBuild = true;

  installPhase = ''
    runHook preInstall

    themeDir="$out/share/plymouth/themes/bcl"
    mkdir -p "$themeDir/progress"

    install -m644 bcl.script "$themeDir"/bcl.script
    install -m644 progress/*.png "$themeDir"/progress/
    install -m644 bcl.plymouth "$themeDir"/bcl.plymouth

    substituteInPlace "$themeDir"/bcl.plymouth \
      --subst-var-by themeDir "$themeDir"

    runHook postInstall
  '';
}
