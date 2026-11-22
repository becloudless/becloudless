package nixos

import (
	"errors"
	"os"
	"path/filepath"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func noopEncrypt(sopsConfigFile string, secretFile string) error {
	return nil
}

func TestAddGroup_CreatesGroupFiles(t *testing.T) {
	infraDirectory := t.TempDir()
	var encryptedConfigFile, encryptedSecretFile string

	groupDirectory, err := AddGroup(AddGroupOptions{
		InfraDirectory:    infraDirectory,
		Name:              "servers",
		Role:              "server",
		AdminAgePublicKey: "age1admin",
		EncryptSecretFile: func(sopsConfigFile string, secretFile string) error {
			encryptedConfigFile = sopsConfigFile
			encryptedSecretFile = secretFile
			return nil
		},
	})

	require.NoError(t, err)
	assert.Equal(t, filepath.Join(infraDirectory, "nixos", "modules", "nixos", "groups", "servers"), groupDirectory)
	assert.Equal(t, filepath.Join(groupDirectory, ".sops.yaml"), encryptedConfigFile)
	assert.Equal(t, filepath.Join(groupDirectory, "default.secrets.yaml"), encryptedSecretFile)

	sopsConfig, err := os.ReadFile(encryptedConfigFile)
	require.NoError(t, err)
	assert.Contains(t, string(sopsConfig), "age1admin")
	assert.Regexp(t, `- age1[a-z0-9]+`, string(sopsConfig))

	secrets, err := os.ReadFile(encryptedSecretFile)
	require.NoError(t, err)
	assert.Contains(t, string(secrets), "ssh_host_ed25519_key: |")
	assert.Contains(t, string(secrets), "initrd_ssh_host_ed25519_key: |")
	assert.Contains(t, string(secrets), "BEGIN OPENSSH PRIVATE KEY")

	nixFile, err := os.ReadFile(filepath.Join(groupDirectory, "default.nix"))
	require.NoError(t, err)
	assert.Equal(t, `{ config, lib, ... }:
{
  config = lib.mkMerge [
    { bcl.group.knownGroups = [ "servers" ]; }
    (lib.mkIf (config.bcl.group.name == "servers") {
      bcl.role.name = "server";
      bcl.role.secretFile = ./default.secrets.yaml;
    })
  ];
}
`, string(nixFile))
}

func TestAddGroup_WithoutRoleOmitsRoleName(t *testing.T) {
	groupDirectory, err := AddGroup(AddGroupOptions{
		InfraDirectory:    t.TempDir(),
		Name:              "servers",
		AdminAgePublicKey: "age1admin",
		EncryptSecretFile: noopEncrypt,
	})

	require.NoError(t, err)
	nixFile, err := os.ReadFile(filepath.Join(groupDirectory, "default.nix"))
	require.NoError(t, err)
	assert.NotContains(t, string(nixFile), "bcl.role.name")
}

func TestAddGroup_RefusesExistingGroup(t *testing.T) {
	options := AddGroupOptions{
		InfraDirectory:    t.TempDir(),
		Name:              "servers",
		AdminAgePublicKey: "age1admin",
		EncryptSecretFile: noopEncrypt,
	}
	groupDirectory, err := AddGroup(options)
	require.NoError(t, err)
	nixFilePath := filepath.Join(groupDirectory, "default.nix")
	require.NoError(t, os.WriteFile(nixFilePath, []byte("mine"), 0644))

	_, err = AddGroup(options)

	assert.Error(t, err)
	nixFile, err := os.ReadFile(nixFilePath)
	require.NoError(t, err)
	assert.Equal(t, "mine", string(nixFile))
}

func TestAddGroup_RemovesGroupDirectoryWhenEncryptionFails(t *testing.T) {
	infraDirectory := t.TempDir()

	groupDirectory, err := AddGroup(AddGroupOptions{
		InfraDirectory:    infraDirectory,
		Name:              "servers",
		AdminAgePublicKey: "age1admin",
		EncryptSecretFile: func(string, string) error { return errors.New("sops failed") },
	})

	assert.Error(t, err)
	assert.Empty(t, groupDirectory)
	assert.NoDirExists(t, filepath.Join(infraDirectory, "nixos", "modules", "nixos", "groups", "servers"))
}

func TestAddGroup_RejectsInvalidInput(t *testing.T) {
	_, err := AddGroup(AddGroupOptions{InfraDirectory: t.TempDir(), Name: "Bad_Name", AdminAgePublicKey: "age1admin", EncryptSecretFile: noopEncrypt})
	assert.Error(t, err)

	_, err = AddGroup(AddGroupOptions{InfraDirectory: t.TempDir(), Name: "servers", EncryptSecretFile: noopEncrypt})
	assert.Error(t, err)
}
