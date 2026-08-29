{config, lib, ...}:
{
  config = lib.mkMerge [
    { bcl.group.knownGroups = [ "test-tv" ]; }
    (lib.mkIf (config.bcl.group.name == "test-tv") {
    bcl.role.name = "tv";
    bcl.role.secretFile = ./default.secrets.yaml;
  })
  ];
}
