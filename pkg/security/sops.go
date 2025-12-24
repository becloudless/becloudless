package security

import (
	"os"

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

// DecryptSopsYAML decrypts a SOPS-encrypted YAML document (".sops" section) using
// the same key sources as the sops CLI (age, pgp, kms, etc.), but in-process.
func DecryptSopsYAML(path string) ([]byte, error) {
	ciphertext, err := os.ReadFile(path)
	if err != nil {
		return nil, errs.WithEF(err, data.WithField("path", path), "Failed to read sops secret file")
	}

	plaintext, err := decrypt.Data(ciphertext, "yaml")
	if err != nil {
		return nil, errs.WithE(err, "Failed to decrypt SOPS YAML")
	}
	return plaintext, nil
}
