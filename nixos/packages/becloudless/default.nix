{ lib, stdenv, fetchFromGitHub, buildGoModule, nixosTests, darwin }:

buildGoModule rec {
  pname = "becloudless";
  version = "0.251227.1733-H004d016";

  src = fetchFromGitHub {
    rev = "r${rev}";
    owner = "becloudless";
    repo = "becloudless";
    hash = "sha256-KwEXA0TOFfOYrhYlfWEC2KeFw+I52DG2GbDLegZif1E=";
  };

  buildPhase = ''
    ./gomake build
  '';

  installPhase = ''
    # Allow go to download the requested toolchain version
    export GOTOOLCHAIN="auto"
  meta = with lib; {
    description = "Tooling to manage whole infrastructure easily";
    mainProgram = "bcl";
    homepage = "https://github.com/becloudless/becloudless";
    changelog = "https://github.com/becloudless/becloudless/releases/tag/v${version}";
    license = licenses.asl20; # TODO
    maintainers = with maintainers; [ n0rad ];
  };
}
