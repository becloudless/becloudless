package nixos

import (
	"fmt"
	"github.com/becloudless/becloudless/pkg/nixos"
	"github.com/n0rad/go-erlog/errs"
	"github.com/n0rad/go-erlog/logs"
	"github.com/spf13/cobra"
	"golang.org/x/term"
	"syscall"
)

func NixosPrepareCmd() *cobra.Command {
	var askPassword bool
	cmd := &cobra.Command{
		Use:   "prepare",
		Short: "prepare system to be able run nix commands",
		RunE: func(cmd *cobra.Command, args []string) error {

			var password []byte
			if askPassword {
				fmt.Print("Sudo password? ")
				pass, err := term.ReadPassword(syscall.Stdin)
				if err != nil {
					return errs.WithE(err, "Failed to read password")
				}
				password = pass
			}

			logs.Info("Checking if nix command is available")
			if err := nixos.EnsureNixIsAvailable(); err != nil {
				logs.WithE(err).Warn("Nix command not found, installing")
				if err := nixos.InstallNixLocally(password); err != nil {
					return errs.WithE(err, "Nix install failed")
				}
				if err := nixos.EnsureNixIsAvailable(); err != nil {
					return errs.WithE(err, "nix command is still not available after install :(")
				}
			}
			logs.Info("Everything looks good")
			return nil
		},
	}
	cmd.Flags().BoolVarP(&askPassword, "ask-password", "P", false, "ask password")
	return cmd
}
