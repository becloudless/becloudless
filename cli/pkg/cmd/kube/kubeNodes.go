package kube

import (
	"github.com/spf13/cobra"
)

func kubeNodesCmd() *cobra.Command {
	cmd := cobra.Command{
		Use:     "nodes",
		Aliases: []string{"node", "n"},
	}
	cmd.AddCommand(
		kubeNodesRemoveCmd(),
	)
	return &cmd
}
