{ lib, stdenv, fetchurl }:

let
  # renovate: datasource=github-releases depName=becloudless/becloudless
  version = "0.260529.740";

  # Map Nix system to Go platform (GOOS-GOARCH format)
  platform = {
    "x86_64-linux"   = "linux-amd64";
    "aarch64-linux"  = "linux-arm64";
    "x86_64-darwin"  = "darwin-amd64";
    "aarch64-darwin" = "darwin-arm64";
  }.${stdenv.hostPlatform.system} or (throw "bcl: unsupported system ${stdenv.hostPlatform.system}");

  # To recompute hashes after a version bump, run for each platform (linux-amd64, linux-arm64, darwin-amd64, darwin-arm64):
  # VERSION=0.260410.550-H89e635b
  # nix store prefetch-file --hash-type sha256 --json "https://github.com/becloudless/becloudless/releases/download/v$VERSION/bcl-linux-amd64.tar.gz" | jq -r .hash
  # nix store prefetch-file --hash-type sha256 --json "https://github.com/becloudless/becloudless/releases/download/v$VERSION/bcl-linux-arm64.tar.gz" | jq -r .hash
  # nix store prefetch-file --hash-type sha256 --json "https://github.com/becloudless/becloudless/releases/download/v$VERSION/bcl-darwin-amd64.tar.gz" | jq -r .hash
  # nix store prefetch-file --hash-type sha256 --json "https://github.com/becloudless/becloudless/releases/download/v$VERSION/bcl-darwin-arm64.tar.gz" | jq -r .hash
  hashes = {
    "linux-amd64" = "sha256-rZfrmW10vJEtBEr8zmElo9pJ6gCHBD4ibf1XP8dDDSc=";
    "linux-arm64" = "sha256-cn6buxRN9LgNiUA2V+H1jRqiAO6m1XJwEOkv7vstPjI=";
    "darwin-amd64" = "sha256-++SgiLNv60p3/96ic2rUxwX0b3LOCHPwXD6FEEZKRSQ=";
    "darwin-arm64" = "sha256-/ge6BAD8pQetv+wrtQPwFUtEUWC3rGalBkxJhF2wrQM=";
  };
in

stdenv.mkDerivation {
  pname = "bcl";
  inherit version;

  src = fetchurl {
    url = "https://github.com/becloudless/becloudless/releases/download/v${version}/bcl-${platform}.tar.gz";
    hash = hashes.${platform};
  };

  sourceRoot = ".";

  installPhase = ''
    mkdir -p $out/bin
    cp bcl-${platform}/bcl $out/bin/bcl
    chmod +x $out/bin/bcl

    mkdir -p $out/share/bash-completion/completions
    $out/bin/bcl completion bash > $out/share/bash-completion/completions/bcl

    mkdir -p $out/share/zsh/site-functions
    $out/bin/bcl completion zsh > $out/share/zsh/site-functions/_bcl

    mkdir -p $out/share/fish/vendor_completions.d
    $out/bin/bcl completion fish > $out/share/fish/vendor_completions.d/bcl.fish
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
