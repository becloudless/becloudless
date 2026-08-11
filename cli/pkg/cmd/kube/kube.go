package kube

import (
	"github.com/becloudless/becloudless/pkg/cmd/kube/chart"
	"github.com/spf13/cobra"
)

func KubeCmd() *cobra.Command {
	cmd := cobra.Command{
		Use:     "kube",
		Aliases: []string{"k"},
		Short:   "Manage Kubernetes resources",
	}
	cmd.AddCommand(
		chart.ChartsCmd(),
		kubeBootstrapCmd(),
		kubeContextCmd(),
		kubeSecretCmd(),
	)
	return &cmd
}
