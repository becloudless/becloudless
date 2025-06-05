package nixos

import (
	"github.com/spf13/cobra"
)

func NixosCmd() *cobra.Command {
	cmd := &cobra.Command{
		Use:     "nixos",
		Aliases: []string{"nix"},
		Short:   "Handle devices with Nix Operating System",
	}
	cmd.AddCommand(
		NixosInstallCmd(),
		NixosIsoCmd(),
		NixosPrepareCmd(),
	)
	return cmd
}
