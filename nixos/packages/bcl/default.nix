{ lib, stdenv, fetchurl }:

let
  # renovate: datasource=github-releases depName=becloudless/becloudless
  version = "0.260425.531-H2ee1181";

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
    "linux-amd64" = "sha256-xQ06BarypCfXWP5HZSNgTLuksZf1aisT76ULlhspKzo=";
    "linux-arm64" = "sha256-8vpl+l1r6QUAcybRwfgNUzjG7gO1D6JD+dufXXxr4lA=";
    "darwin-amd64" = "sha256-9iPCpCDj5dIgX1Gczzl+L8tgXQr+7vZeo8++SX4OEAw=";
    "darwin-arm64" = "sha256-aBRjK8bStWtIpHyjQOFfgQVcM0tq88tgppb/orNveEk=";
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
