{ lib, stdenv, fetchurl, fetchFromGitHub, nixosTests, darwin }:

stdenv.mkDerivation rec {
  pname = "becloudless";
  version = "0.251226.2334-H2ad555e";
  rev = "v${version}";

  src = fetchurl {
    url = "https://github.com/becloudless/becloudless/releases/download/${rev}/bcl-linux-amd64.tar.gz";
    hash = "sha256-itsjTYA3p59x6r+HEwul+lENhrC88iWQ5xRh3DPSVk4=";
  };

  buildPhase = "";

  installPhase = ''
    mkdir -p $out/bin
    tar -xzf $src
    cp bcl $out/bin/bcl
  '';

  meta = with lib; {
    description = "Tooling to manage whole infrastructure easily";
    mainProgram = "bcl";
    homepage = "https://github.com/becloudless/becloudless";
    changelog = "https://github.com/becloudless/becloudless/releases/tag/v${version}";
    license = licenses.asl20;
    maintainers = with maintainers; [ n0rad ];
  };
}
