{ lib, stdenv, fetchurl }:

let
  # renovate: datasource=github-releases depName=becloudless/becloudless extractVersion=^cli-v(?<version>.+)$
  version = "0.260222.1646-H393a363";

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
    "linux-amd64"  = "sha256-3bNbRxxqql6cWnTZoeHyKZqCk8U/C7otZscQAVrTA8o=";
    "linux-arm64"  = "sha256-hpVK8QVzu/CafdMi7y8aSR7rJNApyruo/b3xCu7g+fY=";
    "darwin-amd64" = "sha256-jL1z9qcYtVtpW4V0MQpjxjqOzodXLmN8Jb1a2VH8hJ0=";
    "darwin-arm64" = "sha256-pxZGDJuDtr9OJu1w1D63LMJgEhiYaDtl3JB3QfMpy4k=";
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

