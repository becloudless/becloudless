{ lib, ... }:
{
  imports = lib.filter
              (n: n != ./default.nix && lib.strings.hasSuffix ".nix" (toString n))
              (lib.filesystem.listFilesRecursive ../.);
}