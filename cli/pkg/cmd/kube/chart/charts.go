package chart

import "github.com/spf13/cobra"

func ChartsCmd() *cobra.Command {
	cmd := cobra.Command{
		Use:     "chart",
		Aliases: []string{"chart"},
		Short:   "Manage Kubernetes helm charts",
	}
	cmd.AddCommand(
		buildCmd(),
		//pushCmd(),
	)
	return &cmd
}
