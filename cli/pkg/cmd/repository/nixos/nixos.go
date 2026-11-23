package nixos

import (
	"github.com/spf13/cobra"
)

func NixosCmd() *cobra.Command {
	cmd := &cobra.Command{
		Use:     "nixos",
		Aliases: []string{"nix"},
		Short:   "Handle the nixos part of the infrastructure repository",
	}
	cmd.AddCommand(
		nixosSystemCmd(),
		nixosGroupCmd(),
		nixosHardwareCmd(),
	)
	return cmd
}
