package repository

import (
	"path"

	"github.com/becloudless/becloudless/pkg/bcl"
	"github.com/becloudless/becloudless/pkg/repository"
	"github.com/becloudless/becloudless/pkg/security"
	"github.com/becloudless/becloudless/pkg/system/runner"
	"github.com/n0rad/go-erlog/logs"
	"github.com/spf13/cobra"
)

func repositoryAddNixosGroupCmd() *cobra.Command {
	options := repository.AddNixosGroupOptions{}

	cmd := &cobra.Command{
		Use:   "group <name>",
		Short: "Add a nixos group to the infrastructure repository",
		Long: "Creates nixos/modules/nixos/groups/<name> in the infrastructure repository of the current directory: " +
			"the group module, and its secret file holding new ssh host keys, encrypted with sops for you and for the group. " +
			"An existing group is never overwritten.",
		Args: cobra.ExactArgs(1),
		RunE: func(cmd *cobra.Command, args []string) error {
			infra, err := bcl.FindInfraFromPath(".")
			if err != nil {
				return err
			}

			ed25519KeyFile := path.Join(bcl.BCL.ConfigFolder, bcl.PathSecrets, bcl.PathEd25519KeyFile)
			adminAgePublicKey, _, err := security.Ed25519PrivateKeyFileToPublicAndPrivateAgeKeys(ed25519KeyFile)
			if err != nil {
				return err
			}

			sopsRunner := runner.NewNixShellRunner(runner.NewLocalRunner(), "sops")
			options.Name = args[0]
			options.InfraDirectory = infra.GetRootDir()
			options.AdminAgePublicKey = adminAgePublicKey
			options.EncryptSecretFile = func(sopsConfigFile string, secretFile string) error {
				return sopsRunner.ExecCmd("sops", "--config", sopsConfigFile, "--in-place", "--encrypt", secretFile)
			}

			groupDirectory, err := repository.AddNixosGroup(options)
			if err != nil {
				return err
			}

			logs.WithField("path", groupDirectory).Info("Group created")
			logs.Info("Add the new files to git, flakes ignore untracked files")
			return nil
		},
	}

	cmd.Flags().StringVar(&options.Role, "role", "", "Role of the machines of the group (server, tv, ...)")
	return cmd
}
