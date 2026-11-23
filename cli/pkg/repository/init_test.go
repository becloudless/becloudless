package repository

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func createTemplateDirectory(t *testing.T) string {
	templateDirectory := t.TempDir()
	for _, relativePath := range templateFilePaths {
		filePath := filepath.Join(templateDirectory, relativePath)
		require.NoError(t, os.MkdirAll(filepath.Dir(filePath), 0755))
		require.NoError(t, os.WriteFile(filePath, []byte("template "+relativePath), 0644))
	}
	return templateDirectory
}

func TestInit_CreatesRepositoryFiles(t *testing.T) {
	targetDirectory := filepath.Join(t.TempDir(), "infra")

	result, err := Init(InitOptions{
		TargetDirectory:   targetDirectory,
		TemplateDirectory: createTemplateDirectory(t),
		AgePublicKey:      "age1testkey",
	})

	require.NoError(t, err)
	assert.True(t, result.GitInitiated)
	assert.Empty(t, result.SkippedPaths)
	assert.DirExists(t, filepath.Join(targetDirectory, ".git"))

	flake, err := os.ReadFile(filepath.Join(targetDirectory, "nixos", "flake.nix"))
	require.NoError(t, err)
	assert.Equal(t, "template nixos/flake.nix", string(flake))

	sopsConfig, err := os.ReadFile(filepath.Join(targetDirectory, ".sops.yaml"))
	require.NoError(t, err)
	assert.Contains(t, string(sopsConfig), "- age1testkey")
}

func TestInit_DoesNotOverwriteExistingFiles(t *testing.T) {
	targetDirectory := t.TempDir()
	existingFlakePath := filepath.Join(targetDirectory, "nixos", "flake.nix")
	require.NoError(t, os.MkdirAll(filepath.Dir(existingFlakePath), 0755))
	require.NoError(t, os.WriteFile(existingFlakePath, []byte("mine"), 0644))

	result, err := Init(InitOptions{
		TargetDirectory:   targetDirectory,
		TemplateDirectory: createTemplateDirectory(t),
		AgePublicKey:      "age1testkey",
	})

	require.NoError(t, err)
	assert.Equal(t, []string{"nixos/flake.nix"}, result.SkippedPaths)
	flake, err := os.ReadFile(existingFlakePath)
	require.NoError(t, err)
	assert.Equal(t, "mine", string(flake))
}

func TestInit_DoesNotInitGitInsideExistingRepository(t *testing.T) {
	parentDirectory := t.TempDir()
	_, err := Init(InitOptions{
		TargetDirectory:   parentDirectory,
		TemplateDirectory: createTemplateDirectory(t),
		AgePublicKey:      "age1testkey",
	})
	require.NoError(t, err)

	subDirectory := filepath.Join(parentDirectory, "sub")
	result, err := Init(InitOptions{
		TargetDirectory:   subDirectory,
		TemplateDirectory: createTemplateDirectory(t),
		AgePublicKey:      "age1testkey",
	})

	require.NoError(t, err)
	assert.False(t, result.GitInitiated)
	assert.NoDirExists(t, filepath.Join(subDirectory, ".git"))
}
