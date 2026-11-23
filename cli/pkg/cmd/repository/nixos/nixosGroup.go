package nixos

import (
	"github.com/spf13/cobra"
)

func nixosGroupCmd() *cobra.Command {
	cmd := &cobra.Command{
		Use:     "group",
		Aliases: []string{"groups"},
		Short:   "Handle the nixos groups of the infrastructure repository",
	}
	cmd.AddCommand(
		nixosGroupAddCmd(),
	)
	return cmd
}
