{ lib, stdenv, fetchurl }:

let
  # renovate: datasource=github-releases depName=becloudless/becloudless extractVersion=^cli-v(?<version>.+)$
  version = "0.260303.448-H153758a";

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
    "linux-amd64" = "sha256-/QEoxc0l3jP6AsTpvXPj4tUzWZAdbMUzLdemPqF55jY=";
    "linux-arm64" = "sha256-YDaoLfLyxQbjKSUE/iraffMJ+8NSI9wQ1fR0hNmvfkg=";
    "darwin-amd64" = "sha256-+pCwCHa+e8xMFVoMksIDgdV3UQMSt2T7w6WEMf4hVzM=";
    "darwin-arm64" = "sha256-0vaX/STfgp861HN3bgPzyHb8vNpYMsT/ArR2sxNoXBk=";
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

