{ channels, ... }:
final: prev: {
  nixos-anywhere = prev.nixos-anywhere.overrideAttrs (old: {
    version = "1.6.0";
    src = final.fetchFromGitHub {
      owner = "nix-community";
      repo = "nixos-anywhere";
      rev = "1.6.0";
      hash = "sha256-aoTJqEImmpgsol+TyDASuyHW6tuL7NIS8gusUJ/kxyk=";
    };
  });
}
