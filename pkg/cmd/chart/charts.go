package chart

import "github.com/spf13/cobra"

func ChartCmd() *cobra.Command {
	cmd := cobra.Command{
		Use:     "chart",
		Aliases: []string{"charts"},
	}
	cmd.AddCommand(
		buildCmd(),
		//pushCmd(),
	)
	return &cmd
}
