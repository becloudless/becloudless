{ lib, ... }:
{
  imports = lib.filter
              (n: !(lib.strings.hasSuffix "/default.nix" (toString n)) && lib.strings.hasSuffix ".nix" (toString n))
              (lib.filesystem.listFilesRecursive ../.);
}