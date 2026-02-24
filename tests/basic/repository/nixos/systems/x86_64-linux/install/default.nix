{ modulesPath, ... }:
{
  # nix build .#nixosConfigurations.install.config.system.build.isoImage --impure
  imports = [ "${modulesPath}/installer/cd-dvd/installation-cd-minimal.nix" ];
  bcl.role.name = "install";
}
