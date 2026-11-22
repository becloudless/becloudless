package repository

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestAddNixosSystem_WritesSystemFile(t *testing.T) {
	infraDirectory := t.TempDir()

	systemFile, err := AddNixosSystem(AddNixosSystemOptions{
		InfraDirectory:  infraDirectory,
		Name:            "server1",
		Group:           "server",
		Hardware:        "nuc",
		Devices:         []string{"/dev/nvme0n1"},
		MotherboardUuid: "abc-123",
		NetworkMacs:     []string{"aa:bb:cc:dd:ee:ff"},
	})

	require.NoError(t, err)
	assert.Equal(t, filepath.Join(infraDirectory, "nixos", "systems", "x86_64-linux", "server1", "default.nix"), systemFile)
	content, err := os.ReadFile(systemFile)
	require.NoError(t, err)
	assert.Equal(t, `{
  bcl.system = {
    hardware = "nuc";
    group = "server";
    devices = [ "/dev/nvme0n1" ];
    id.motherboardUuid = "abc-123";
    id.networkMacs = [ "aa:bb:cc:dd:ee:ff" ];
  };
}
`, string(content))
}

func TestAddNixosSystem_MinimalSystemAndArchitecture(t *testing.T) {
	infraDirectory := t.TempDir()

	systemFile, err := AddNixosSystem(AddNixosSystemOptions{
		InfraDirectory: infraDirectory,
		Name:           "pi",
		Architecture:   "aarch64-linux",
		Group:          "server",
	})

	require.NoError(t, err)
	assert.Contains(t, systemFile, filepath.Join("systems", "aarch64-linux", "pi"))
	content, err := os.ReadFile(systemFile)
	require.NoError(t, err)
	assert.Equal(t, "{\n  bcl.system = {\n    group = \"server\";\n  };\n}\n", string(content))
}

func TestAddNixosSystem_RefusesExistingSystem(t *testing.T) {
	infraDirectory := t.TempDir()
	options := AddNixosSystemOptions{InfraDirectory: infraDirectory, Name: "server1", Group: "server"}
	_, err := AddNixosSystem(options)
	require.NoError(t, err)

	_, err = AddNixosSystem(options)

	assert.Error(t, err)
}

func TestAddNixosSystem_RejectsInvalidInput(t *testing.T) {
	infraDirectory := t.TempDir()

	_, err := AddNixosSystem(AddNixosSystemOptions{InfraDirectory: infraDirectory, Name: "Bad_Name", Group: "server"})
	assert.Error(t, err)

	_, err = AddNixosSystem(AddNixosSystemOptions{InfraDirectory: infraDirectory, Name: "server1"})
	assert.Error(t, err)
}

func TestNixString_EscapesSpecialCharacters(t *testing.T) {
	assert.Equal(t, `"a\"b\\c\${d}"`, nixString(`a"b\c${d}`))
}
