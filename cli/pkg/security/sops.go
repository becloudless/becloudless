package security

import (
	"os"

	"github.com/getsops/sops/v3/cmd/sops/formats"
	"github.com/getsops/sops/v3/decrypt"
	"github.com/n0rad/go-erlog/data"
	"github.com/n0rad/go-erlog/errs"
)

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

func DecryptSopsYAMLWithAgeKey(path string, ageKey string) ([]byte, error) {
	if ageKey != "" {
		if err := os.Setenv("SOPS_AGE_KEY", ageKey); err != nil {
			return nil, errs.WithE(err, "Failed to set SOPS_AGE_KEY environment variable")
		}
		defer os.Setenv("SOPS_AGE_KEY", "")
	}
	ciphertext, err := os.ReadFile(path)
	if err != nil {
		return nil, errs.WithEF(err, data.WithField("path", path), "Failed to read sops secret file")
	}

	plaintext, err := decrypt.DataWithFormat(ciphertext, formats.Yaml)
	if err != nil {
		return nil, errs.WithEF(err, data.WithField("path", path), "Failed to decrypt SOPS YAML")
	}
	return plaintext, nil
}
