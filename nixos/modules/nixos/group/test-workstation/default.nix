{inputs, config, lib, ...}:
{
  config = lib.mkIf (config.bcl.group.name == "test-workstation") (inputs.yaml.lib.fromYaml ./default.yaml);
}
