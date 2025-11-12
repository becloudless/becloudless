package utils

import "github.com/spf13/cobra"

func UtilsCmd() *cobra.Command {
	cmd := &cobra.Command{
		Use: "utils",
	}
	cmd.AddCommand(
		utilsSsh2AgeCmd(),
	)
	return cmd
}
