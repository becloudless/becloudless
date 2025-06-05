package nixos

import (
	"github.com/becloudless/becloudless/pkg/nixos"
	"github.com/n0rad/go-erlog/errs"
	"github.com/n0rad/go-erlog/logs"
	"github.com/spf13/cobra"
)

func NixosPrepareCmd() *cobra.Command {
	cmd := &cobra.Command{
		Use:   "prepare",
		Short: "prepare system to be able run nix commands",
		RunE: func(cmd *cobra.Command, args []string) error {
			logs.Info("Checking if nix command is available")
			if err := nixos.EnsureNixIsAvailable(); err != nil {
				logs.WithE(err).Warn("Nix command not found, installing")
				if err := nixos.InstallNixLocally(); err != nil {
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
	return cmd
}
