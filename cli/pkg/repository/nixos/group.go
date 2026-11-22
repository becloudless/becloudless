package nixos

import (
	"fmt"
	"os"
	"path/filepath"

	bclnixos "github.com/becloudless/becloudless/pkg/nixos"
	"github.com/becloudless/becloudless/pkg/security"
	"github.com/becloudless/becloudless/pkg/utils"
	"github.com/n0rad/go-erlog/data"
	"github.com/n0rad/go-erlog/errs"
)

const groupSecretFileName = "default.secrets.yaml"

type AddGroupOptions struct {
	InfraDirectory    string
	Name              string
	Role              string
	AdminAgePublicKey string
	// EncryptSecretFile encrypts the file in place with the sops configuration file
	EncryptSecretFile func(sopsConfigFile string, secretFile string) error
}

// AddGroup returns the created group directory, it never overwrites an existing group.
// The group secret file holds the ssh host keys of the machines of the group, encrypted for the
// admin and for the age key derived from the group host key.
func AddGroup(options AddGroupOptions) (createdGroupDirectory string, resultError error) {
	if !namePattern.MatchString(options.Name) {
		return "", errs.WithF(data.WithField("name", options.Name), "Group name must be lowercase letters, digits and dashes")
	}
	if options.AdminAgePublicKey == "" {
		return "", errs.With("Admin age public key is required")
	}

	groupDirectory := filepath.Join(options.InfraDirectory, "nixos", "modules", "nixos", "groups", options.Name)
	groupField := data.WithField("directory", groupDirectory)

	if _, err := os.Stat(groupDirectory); err == nil {
		return "", errs.WithF(groupField, "Group already exists")
	} else if !os.IsNotExist(err) {
		return "", errs.WithEF(err, groupField, "Failed to check group directory")
	}
	if err := os.MkdirAll(groupDirectory, 0755); err != nil {
		return "", errs.WithEF(err, groupField, "Failed to create group directory")
	}
	defer func() {
		if resultError != nil {
			_ = os.RemoveAll(groupDirectory)
		}
	}()

	_, hostPrivateKey, err := security.NewPublicAndPrivatePenEd25519Key()
	if err != nil {
		return "", err
	}
	_, initrdPrivateKey, err := security.NewPublicAndPrivatePenEd25519Key()
	if err != nil {
		return "", err
	}
	hostAgePublicKey, _, err := security.Ed25519ToPublicAndPrivateAgeKeys(hostPrivateKey)
	if err != nil {
		return "", err
	}

	sopsConfigFile := filepath.Join(groupDirectory, security.SopsConfigFileName)
	sopsConfig := security.ConfigFile{CreationRules: []security.CreationRule{
		{KeyGroups: []security.KeyGroup{{Age: []string{options.AdminAgePublicKey, hostAgePublicKey}}}},
	}}
	if err := utils.YamlMarshalToFile(sopsConfigFile, sopsConfig, 0644); err != nil {
		return "", err
	}

	secretFile := filepath.Join(groupDirectory, groupSecretFileName)
	secrets := bclnixos.GroupSecretFile{
		SshHostEd25519Key:       string(hostPrivateKey),
		InitrdSshHostEd25519Key: string(initrdPrivateKey),
	}
	if err := utils.YamlMarshalToFile(secretFile, secrets, 0600); err != nil {
		return "", err
	}
	if err := options.EncryptSecretFile(sopsConfigFile, secretFile); err != nil {
		return "", errs.WithEF(err, groupField, "Failed to encrypt group secret file")
	}

	nixFile := filepath.Join(groupDirectory, "default.nix")
	if err := os.WriteFile(nixFile, []byte(renderGroup(options.Name, options.Role)), 0644); err != nil {
		return "", errs.WithEF(err, groupField, "Failed to write group file")
	}
	return groupDirectory, nil
}

func renderGroup(name string, role string) string {
	roleLine := ""
	if role != "" {
		roleLine = fmt.Sprintf("      bcl.role.name = %s;\n", nixString(role))
	}
	return fmt.Sprintf(`{ config, lib, ... }:
{
  config = lib.mkMerge [
    { bcl.group.knownGroups = [ %[1]s ]; }
    (lib.mkIf (config.bcl.group.name == %[1]s) {
%[2]s      bcl.role.secretFile = ./%[3]s;
    })
  ];
}
`, nixString(name), roleLine, groupSecretFileName)
}
