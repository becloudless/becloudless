{ lib, buildGo124Module, fetchFromGitHub }:

buildGo124Module rec {
  pname = "becloudless";
  version = "0.251226.2334-H2ad555e";

  src = fetchFromGitHub {
    owner = "becloudless";
    repo = "becloudless";
    rev = "v${version}";
    hash = "";
  };

  vendorHash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";

  buildPhase = ''
#    export HOME=$PWD
    ./gomake build
  '';

  installPhase = ''
    mkdir -p $out/bin
    cp dist/bcl-linux-amd64/bcl $out/bin/bcl
  '';

  meta = with lib; {
    description = "Tool to manage whole infrastructure easily";
    mainProgram = "bcl";
    homepage = "https://github.com/becloudless/becloudless";
    changelog = "https://github.com/becloudless/becloudless/releases/tag/v${version}";
    license = licenses.asl20;
    maintainers = with maintainers; [ n0rad ];
  };
}
