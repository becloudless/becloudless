{config, lib, ...}:
{
  config = lib.mkIf (config.bcl.group.name == "install") {
    bcl.role.name = "install";
    bcl.role.secretFile = ./default.secrets.yaml;
  };
}
