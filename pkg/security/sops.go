package security

const SopsConfigFileName = ".sops.yaml"

// configFile is not public on getsops/sops/config
type ConfigFile struct {
	CreationRules []CreationRule `yaml:"creation_rules"`
}

type CreationRule struct {
	KeyGroups []KeyGroup `yaml:"key_groups"`
}

type KeyGroup struct {
	Age []string `yaml:"age"`
}
