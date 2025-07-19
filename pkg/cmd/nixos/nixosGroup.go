package nixos

import (
	"github.com/spf13/cobra"
)

func nixosGroupCmd() *cobra.Command {
	cmd := &cobra.Command{
		Use:     "groups",
		Aliases: []string{"group"},
		Short:   "Handle nixos groups",
	}
	cmd.AddCommand(
		nixosGroupCreateCmd(),
	)
	return cmd
}
