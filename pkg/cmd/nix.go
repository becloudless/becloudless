package cmd

import (
	"github.com/spf13/cobra"
)

func NixCmd() *cobra.Command {
	cmd := &cobra.Command{
		Use:   "nix",
		Short: "Handle devices with nix operating system",
	}
	cmd.AddCommand(
		NixInstallCmd(),
		NixIsoCmd(),
	)
	return cmd
}
