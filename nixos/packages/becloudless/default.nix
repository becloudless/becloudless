{ lib, buildGo124Module, fetchFromGitHub, git }:

buildGo124Module rec {
  pname = "becloudless";
  version = "0.251226.2334-H2ad555e";

  src = fetchFromGitHub {
    owner = "becloudless";
    repo = "becloudless";
    rev = "v${version}";
    hash = "sha256-2tA7mz7cqG9tfpVH/M4wKFmb5PNaIpHZcWWJIUk3zwY=";
  };

  vendorHash = "sha256-iDofwnMmUGOy0CzrtIH7rwJRiHp+3Pqlshq5k1VqTcE=";

  nativeBuildInputs = [ git ];

  preBuild = ''
    export HOME=$PWD
    git config --global user.email "you@example.com"
    git config --global user.name "Your Name"
    git config --global init.defaultBranch main
    git init .
    git add .
    git commit -m "init" || true
    ./gomake build
  '';

  buildPhase = ''
    ls
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
