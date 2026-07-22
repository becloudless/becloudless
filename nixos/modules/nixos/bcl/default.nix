{ lib, ... }:
{
  # Nested `default.nix` files (e.g. role/default.nix) are already wired in as
  # their own namespaced modules by snowfall-lib's folder convention, so they
  # must be excluded here to avoid importing (and thus declaring their
  # options) twice.
  imports = lib.filter
              (n: lib.strings.hasSuffix ".nix" (toString n) && baseNameOf (toString n) != "default.nix")
              (lib.filesystem.listFilesRecursive ../.);
}