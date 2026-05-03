package kube

import "github.com/spf13/cobra"

func kubeSecretCmd() *cobra.Command {
	cmd := cobra.Command{
		Use:     "secret",
		Aliases: []string{"secrets"},
		Short:   "Manage Kubernetes secrets",
	}
	cmd.AddCommand(
		kubeSecretExtractCmd(),
	)
	return &cmd
}
