package repository

import (
	"fmt"
	"os"
	"path/filepath"

	"github.com/becloudless/becloudless/pkg/git"
	"github.com/becloudless/becloudless/pkg/security"
	"github.com/n0rad/go-erlog/data"
	"github.com/n0rad/go-erlog/errs"
)

const sopsConfigTemplate = `# Secrets are encrypted with the age key derived from the ed25519 key of the creator.
# Add the age public keys of other users and of the machines that must decrypt them.
creation_rules:
  - path_regex: .*\.(secrets|enc)\.yaml$
    key_groups:
      - age:
          - %s
`

// templateFilePaths are relative to both the template and the repository directories
var templateFilePaths = []string{
	".gitignore",
	"nixos/flake.nix",
	"kube/clusters/.env",
}

type InitOptions struct {
	TargetDirectory   string
	TemplateDirectory string
	AgePublicKey      string
}

type InitResult struct {
	CreatedPaths []string
	SkippedPaths []string
	GitInitiated bool
}

// Init never overwrites an existing file
func Init(options InitOptions) (*InitResult, error) {
	targetField := data.WithField("directory", options.TargetDirectory)
	if err := os.MkdirAll(options.TargetDirectory, 0755); err != nil {
		return nil, errs.WithEF(err, targetField, "Failed to create repository directory")
	}

	result := &InitResult{}

	if _, err := git.OpenRepository(options.TargetDirectory); err != nil {
		if _, err := git.InitRepository(options.TargetDirectory); err != nil {
			return nil, err
		}
		result.GitInitiated = true
	}

	for _, relativePath := range templateFilePaths {
		if err := copyTemplateFile(options, relativePath, result); err != nil {
			return nil, err
		}
	}

	sopsConfigContent := fmt.Sprintf(sopsConfigTemplate, options.AgePublicKey)
	if err := writeFileIfMissing(options.TargetDirectory, security.SopsConfigFileName, []byte(sopsConfigContent), result); err != nil {
		return nil, err
	}

	return result, nil
}

func copyTemplateFile(options InitOptions, relativePath string, result *InitResult) error {
	content, err := os.ReadFile(filepath.Join(options.TemplateDirectory, relativePath))
	if err != nil {
		return errs.WithEF(err, data.WithField("path", relativePath), "Failed to read repository template file")
	}
	return writeFileIfMissing(options.TargetDirectory, relativePath, content, result)
}

func writeFileIfMissing(targetDirectory string, relativePath string, content []byte, result *InitResult) error {
	filePath := filepath.Join(targetDirectory, relativePath)
	fileField := data.WithField("path", filePath)

	if _, err := os.Stat(filePath); err == nil {
		result.SkippedPaths = append(result.SkippedPaths, relativePath)
		return nil
	} else if !os.IsNotExist(err) {
		return errs.WithEF(err, fileField, "Failed to check repository file")
	}

	if err := os.MkdirAll(filepath.Dir(filePath), 0755); err != nil {
		return errs.WithEF(err, fileField, "Failed to create repository file directory")
	}
	if err := os.WriteFile(filePath, content, 0644); err != nil {
		return errs.WithEF(err, fileField, "Failed to write repository file")
	}
	result.CreatedPaths = append(result.CreatedPaths, relativePath)
	return nil
}
