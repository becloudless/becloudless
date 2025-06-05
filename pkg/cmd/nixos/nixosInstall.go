package nixos

import (
	"github.com/becloudless/becloudless/pkg/nixos"
	"github.com/n0rad/go-erlog/errs"
	"github.com/n0rad/go-erlog/logs"
	"github.com/n0rad/memguarded"
	"github.com/spf13/cobra"
)

func NixosInstallCmd() *cobra.Command {
	var host string
	var user string
	var askPassword bool
	cmd := &cobra.Command{
		Use:   "install [HOST_IP]",
		Short: "Install remote device",
		Args:  cobra.ExactArgs(1),
		RunE: func(cmd *cobra.Command, args []string) error {
			host = args[0]
			if err := nixos.EnsureNixIsAvailable(); err != nil {
				return errs.WithE(err, "Nix is not available")
			}

			sudoPasswordService := memguarded.Service{}
			if askPassword {
				if err := sudoPasswordService.AskSecret(false, "Sudo password on host to install? "); err != nil {
					return errs.WithE(err, "Failed to grab sudo password")
				}
			}

			return nixos.InstallAnywhere(host, user, &sudoPasswordService)
		},
	}
	cmd.Flags().StringVarP(&user, "user", "u", "install", "user for the connection")
	cmd.Flags().BoolVarP(&askPassword, "ask-password", "P", false, "ask password")

	if err := cmd.MarkFlagRequired("host"); err != nil {
		logs.WithE(err).Fatal("failed")
	}
	return cmd
}
