package nixos

import (
	"fmt"
	"github.com/becloudless/becloudless/pkg/nixos"
	"github.com/n0rad/go-erlog/errs"
	"github.com/spf13/cobra"
	"golang.org/x/term"
	"syscall"
)

func nixosInstallCmd() *cobra.Command {
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

			var password []byte
			if askPassword {
				fmt.Print("Password on host to install? ")
				pass, err := term.ReadPassword(syscall.Stdin)
				if err != nil {
					return errs.WithE(err, "Failed to read password")
				}
				password = pass
			}

			return nixos.InstallAnywhere(host, user, password)
		},
	}
	cmd.Flags().StringVarP(&user, "user", "u", "nixos", "user for the connection")
	cmd.Flags().BoolVarP(&askPassword, "ask-password", "P", false, "ask password")
	return cmd
}
