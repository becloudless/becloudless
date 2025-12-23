package kube

import "github.com/spf13/cobra"

func KubeCmd() *cobra.Command {
	cmd := cobra.Command{
		Use:     "kube",
		Aliases: []string{"k"},
	}
	cmd.AddCommand(
		bootstrap(),
		context(),
	)
	return &cmd
}
