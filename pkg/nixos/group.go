package nixos

import (
	"github.com/becloudless/becloudless/pkg/bcl"
	"github.com/becloudless/becloudless/pkg/security"
	"github.com/becloudless/becloudless/pkg/system/runner"
	"github.com/becloudless/becloudless/pkg/utils"
	"github.com/n0rad/go-erlog/data"
	"github.com/n0rad/go-erlog/errs"
	"os"
	"path"
)

const sshHostSecretKeyName = "ssh_host_ed25519_key"

func CreateGroup(name string) error {
	groupDir := path.Join(bcl.BCL.Repository.Root, "nixos", "modules", "nixos", "group", name)
	if _, err := os.Stat(groupDir); err == nil {
		return errs.WithEF(err, data.WithField("group", name), "Group already exists")
	} else if !os.IsNotExist(err) {
		return errs.WithEF(err, data.WithField("dir", groupDir), "Failed to read directory")
	}

	if err := os.MkdirAll(groupDir, 0755); err != nil {
		return errs.WithE(err, "Failed to create group dir")
	}

	_, hostPriv, err := security.NewPublicAndPrivatePenEd25519Key()
	if err != nil {
		return err
	}
	hostAgePublic, _, err := security.Ed25519ToPublicAndPrivateAgeKeys(hostPriv)
	if err != nil {
		return err
	}

	adminPub, _, err := security.Ed25519PrivateKeyFileToPublicAndPrivateAgeKeys(path.Join(bcl.BCL.Home, bcl.PathSecrets, bcl.PathEd25519KeyFile))
	if err != nil {
		return err
	}

	if err := createSopsConfigFile(groupDir, []string{adminPub, hostAgePublic}); err != nil {
		return errs.WithE(err, "Failed to create group sops configuration file")
	}

	content := struct {
		SshHostEd25519Key string `yaml:"ssh_host_ed25519_key"`
	}{
		string(hostPriv),
	}
	secretFile := path.Join(groupDir, "default.secrets.yaml")
	if err = utils.YamlMarshalToFile(secretFile, content, 0600); err != nil {
		_ = os.Remove(secretFile)
		return errs.WithE(err, "Failed to create unencrypted secret file")
	}

	sopsRunner := runner.NewNixShellRunner(&runner.LocalRunner{}, "sops")
	if err = sopsRunner.ExecCmd("sops", "--config", path.Join(groupDir, security.SopsConfigFileName), "-i", "-e", secretFile); err != nil {
		_ = os.Remove(secretFile)
		return errs.WithE(err, "Failed to encrypt secret file")
	}

	// create yaml file
	// create nix file
	return nil
}

func createSopsConfigFile(dir string, agePublicKeys []string) error {
	cfg := security.ConfigFile{
		CreationRules: []security.CreationRule{
			{
				KeyGroups: []security.KeyGroup{
					{
						Age: agePublicKeys,
					},
				},
			},
		},
	}
	return utils.YamlMarshalToFile(path.Join(dir, security.SopsConfigFileName), cfg, 0644)
}
