# TODO: Remove once nixpkgs is updated (https://github.com/NixOS/nixpkgs/pull/522930)
# Mirrors https://github.com/r-ryantm/nixpkgs/commit/0a22c82e7765034aa210d581608266b368e89f2e
{ ... }:
final: prev: {
  cef-binary = prev.cef-binary.override {
    version = "149.0.4";
    gitRevision = "2f1bfd8";
    chromiumVersion = "149.0.7827.156";
    srcHashes = {
      aarch64-linux = "sha256-iQmnlonux7I+2ACEtpdmlS1E4A+aNFgylRsykD+KgKA=";
      x86_64-linux = "sha256-bUNgdnXkfta/pA0c/OE20E53IFKfjxxENdS6Hc0YObI=";
    };
  };
}
