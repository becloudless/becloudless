package repository

import (
	"path"

	"github.com/becloudless/becloudless/pkg/bcl"
	"github.com/becloudless/becloudless/pkg/repository"
	"github.com/becloudless/becloudless/pkg/security"
	"github.com/n0rad/go-erlog/logs"
	"github.com/spf13/cobra"
)

func repositoryInitCmd() *cobra.Command {
	cmd := &cobra.Command{
		Use:   "init [directory]",
		Short: "Initialize an infrastructure repository (git, nixos flake, sops, kube) in the directory, current by default",
		Long:  "Existing files are never overwritten.",
		Args:  cobra.MaximumNArgs(1),
		RunE: func(cmd *cobra.Command, args []string) error {
			targetDirectory := "."
			if len(args) == 1 {
				targetDirectory = args[0]
			}

			ed25519KeyFile := path.Join(bcl.BCL.ConfigFolder, bcl.PathSecrets, bcl.PathEd25519KeyFile)
			agePublicKey, _, err := security.Ed25519PrivateKeyFileToPublicAndPrivateAgeKeys(ed25519KeyFile)
			if err != nil {
				return err
			}

			result, err := repository.Init(repository.InitOptions{
				TargetDirectory:   targetDirectory,
				TemplateDirectory: path.Join(bcl.BCL.EmbeddedPath, "assets", "repository"),
				AgePublicKey:      agePublicKey,
			})
			if err != nil {
				return err
			}

			if result.GitInitiated {
				logs.WithField("directory", targetDirectory).Info("Git repository initialized")
			}
			for _, createdPath := range result.CreatedPaths {
				logs.WithField("path", createdPath).Info("Created")
			}
			for _, skippedPath := range result.SkippedPaths {
				logs.WithField("path", skippedPath).Warn("Already exists, kept")
			}
			return nil
		},
	}
	return cmd
}
