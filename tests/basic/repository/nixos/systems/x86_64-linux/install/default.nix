{ modulesPath, ... }:
{
  imports = [ "${modulesPath}/installer/cd-dvd/installation-cd-minimal.nix" ];
  bcl.role.name = "install";
}
