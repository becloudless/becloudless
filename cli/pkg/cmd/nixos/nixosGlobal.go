package nixos

import "github.com/spf13/cobra"

func nixosGlobalCmd() *cobra.Command {
	cmd := &cobra.Command{
		Use:     "globals",
		Aliases: []string{"global"},
		Short:   "Handle nixos global part",
	}
	cmd.AddCommand(
		nixosGlobalEditCmd(),
	)
	return cmd
}
