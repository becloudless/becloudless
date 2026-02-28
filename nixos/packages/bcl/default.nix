{ lib, stdenv, fetchurl }:

let
  # renovate: datasource=github-releases depName=becloudless/becloudless extractVersion=^cli-v(?<version>.+)$
  version = "0.260227.1850-Hd077459";

  # Map Nix system to Go platform (GOOS-GOARCH format)
  platform = {
    "x86_64-linux"   = "linux-amd64";
    "aarch64-linux"  = "linux-arm64";
    "x86_64-darwin"  = "darwin-amd64";
    "aarch64-darwin" = "darwin-arm64";
  }.${stdenv.hostPlatform.system} or (throw "bcl: unsupported system ${stdenv.hostPlatform.system}");

  # To recompute hashes after a version bump, run for each platform (linux-amd64, linux-arm64, darwin-amd64, darwin-arm64):
  #   nix store prefetch-file --hash-type sha256 --json "https://github.com/becloudless/becloudless/releases/download/cli-v<version>/bcl-<platform>.tar.gz" | jq -r .hash
  hashes = {
    "linux-amd64" = "sha256-p06RK18YVrmIw+RMXQjzCkQSiM753AicckcS07WR4us=";
    "linux-arm64" = "sha256-Mx4+Nrq7YGuiW7SsmQ7yIedds0/hNLj196bso6vzKvo=";
    "darwin-amd64" = "sha256-iVMvqurZL28C8K7AvkLYskOLwG3R8Qoblv05YQA0Tqg=";
    "darwin-arm64" = "sha256-feDwPWnh8TPUPSd2l7fZTZ99/Bljk4DbT2rrRV166t0=";
  };
in

stdenv.mkDerivation {
  pname = "bcl";
  inherit version;

  src = fetchurl {
    url = "https://github.com/becloudless/becloudless/releases/download/cli-v${version}/bcl-${platform}.tar.gz";
    hash = hashes.${platform};
  };

  sourceRoot = ".";

  installPhase = ''
    mkdir -p $out/bin
    cp bcl-${platform}/bcl $out/bin/bcl
    chmod +x $out/bin/bcl
  '';

  meta = with lib; {
    description = "BeCloudless CLI tool";
    homepage = "https://github.com/becloudless/becloudless";
    license = licenses.asl20;
    mainProgram = "bcl";
    platforms = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
    maintainers = with maintainers; [ n0rad ];
  };
}

