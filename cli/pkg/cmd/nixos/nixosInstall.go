package nixos

import (
	"os"

	"github.com/becloudless/becloudless/pkg/nixos"
	"github.com/becloudless/becloudless/pkg/system/runner"
	"github.com/n0rad/go-erlog/errs"
	"github.com/n0rad/go-erlog/logs"
	"github.com/n0rad/memguarded"
	"github.com/spf13/cobra"
)

func nixosInstallCmd() *cobra.Command {
	var diskPassword string
	var diskPasswordFile string

	var sshConfig runner.SshConnectionConfig
	sudoPassword := memguarded.NewService()
	sshConfig.Password = sudoPassword

	cmd := &cobra.Command{
		Use:   "install ...",
		Short: "Install remote device",
		RunE: func(cmd *cobra.Command, args []string) error {
			if err := nixos.EnsureNixIsAvailable(); err != nil {
				return errs.WithE(err, "Nix is not available")
			}

			if diskPasswordFile != "" {
				content, err := os.ReadFile(diskPasswordFile)
				if err != nil {
					return errs.WithE(err, "Failed to read disk password file")
				}
				diskPassword = string(content)
			}

			return nixos.InstallAnywhere(&sshConfig, diskPassword)
		},
	}

	withSSHRemoteFlags(cmd, &sshConfig)

	if err := cmd.MarkFlagRequired("host"); err != nil {
		logs.WithE(err).Fatal("Failed to mark host flag as required")
	}

	cmd.Flags().StringVar(&diskPassword, "disk-password", "", "disk password")
	cmd.Flags().StringVar(&diskPasswordFile, "disk-password-file", "", "disk password file")
	return cmd
}
