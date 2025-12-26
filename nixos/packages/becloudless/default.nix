{ lib, stdenv, buildGoModule, fetchFromGitHub, nixosTests, darwin }:

buildGoModule rec {
  pname = "becloudless";
  version = "0.251226.2334-H2ad555e";
  rev = "v${version}";

  src = fetchFromGitHub {
    inherit rev;
    owner = "becloudless";
    repo = "becloudless";
    hash = "sha256-2tA7mz7cqG9tfpVH/M4wKFmb5PNaIpHZcWWJIUk3zwY";
  };

  vendorHash = "";

  buildPhase = ''
    ./gomake build
  '';

  installPhase = ''
    mkdir -p $out/bin
    cp dist/bcl-linux-amd64/bcl $out/bin/bcl
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
