{ lib, stdenv, fetchFromGitHub, buildGo124Module, nixosTests, darwin }:

buildGo124Module rec {
  pname = "becloudless";
  version = "d8cf9f2dff60f3973a3373ad3c9915633f232666";

  src = fetchFromGitHub {
    rev = "${version}";
    owner = "becloudless";
    repo = "becloudless";
    hash = "sha256-+DO1TSGoEgXgtgCBtuEi2LIy2PEVGyy8aX0eG/mNp9I=";
  };

  vendorHash = "";

  buildPhase = ''
    ./gomake build
  '';

  installPhase = ''
    mkdir -p $out/bin
    cp ./bin/bcl $out/bin/
  '';
  meta = with lib; {
    description = "Tooling to manage whole infrastructure easily";
    mainProgram = "bcl";
    homepage = "https://github.com/becloudless/becloudless";
    changelog = "https://github.com/becloudless/becloudless/releases/tag/v${version}";
    license = licenses.asl20; # TODO
    maintainers = with maintainers; [ n0rad ];
  };
}
