{ channels, ... }:
final: prev: {
  nixos-anywhere = prev.nixos-anywhere.overrideAttrs (old: {
    version = "1.11.0";
    src = final.fetchFromGitHub {
      owner = "nix-community";
      repo = "nixos-anywhere";
      rev = "1.11.0";
      hash = "sha256-hVTCvMnwywxQ6rGgO7ytBiSpVuLOHNgm3w3vE8UNaQY=";
    };
  });
}
