{config, lib, ...}:
{
  config = lib.mkIf (config.bcl.group.name == "test-workstation") {
    bcl.group.role = "workstation";
  };
}
