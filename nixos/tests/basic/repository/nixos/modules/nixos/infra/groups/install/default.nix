{config, lib, ...}:
{
  config = lib.mkMerge [
    { bcl.group.knownGroups = [ "install" ]; }
    (lib.mkIf (config.bcl.group.name == "install") {
    bcl.role.name = "install";
    bcl.role.secretFile = ./default.secrets.yaml;
  })
  ];
}
