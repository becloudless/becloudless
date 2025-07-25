{config, lib, ...}:
{
  config = lib.mkIf (config.bcl.group.name == "test-workstation") {
    bcl.role.name = "workstation";
    bcl.group.secretFile = ./default.secrets.yaml;
  };
}