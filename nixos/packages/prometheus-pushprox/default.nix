{ lib, stdenv, buildGoModule, fetchFromGitHub, nixosTests, darwin }:

buildGoModule rec {
  pname = "prometheus-pushprox";
  version = "0.2.0";
  rev = "v${version}";

  env.CGO_ENABLED = 0;

  src = fetchFromGitHub {
    inherit rev;
    owner = "prometheus-community";
    repo = "PushProx";
    hash = "sha256-r96HMv34llkoAeFS37TpSvG7By8CM52Sfo2uC9uUpu8";
  };

  vendorHash = "sha256-K98Ay3H7/RAoKxB5A1h6C2XZqKNXJYvlwqrY2AEKLLs=";

  installPhase = ''
    mkdir -p $out/bin
    cp $GOPATH/bin/client $out/bin/pushprox-client
    cp $GOPATH/bin/proxy $out/bin/pushprox-proxy
  '';

  meta = with lib; {
    description = "Proxy to allow Prometheus to scrape through NAT etc.";
    mainProgram = "pushprox-client";
    homepage = "https://github.com/prometheus-community/PushProx";
    changelog = "https://github.com/prometheus-community/PushProx/blob/v${version}/CHANGELOG.md";
    license = licenses.asl20;
    maintainers = with maintainers; [ n0rad ];
  };

}
