package nixos

import (
	"github.com/spf13/cobra"
)

func nixosSystemCmd() *cobra.Command {
	cmd := &cobra.Command{
		Use:     "system",
		Aliases: []string{"systems"},
		Short:   "Handle the nixos systems of the infrastructure repository",
	}
	cmd.AddCommand(
		nixosSystemAddCmd(),
	)
	return cmd
}
