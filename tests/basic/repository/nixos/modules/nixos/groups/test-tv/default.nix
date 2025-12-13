{config, lib, ...}:
{
  config = lib.mkIf (config.bcl.group.name == "test-tv") {
    bcl.role.name = "tv";
    bcl.role.secretFile = ./default.secrets.yaml;
  };
}
