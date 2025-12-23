package kube

import (
	"github.com/becloudless/becloudless/pkg/kube"
	"github.com/spf13/cobra"
)

func bootstrap() *cobra.Command {
	cmd := cobra.Command{
		Use:   "bootstrap",
		Short: "Bootstrap Kubernetes clusters till Flux being able to take over and apply gitops",
		Long: `The bootstrap command manually apply the necessary components, especially networking and Flux, till being able to hand over to Flux for gitops.
				  This script is re-entrant, and apply the components, like they are applied by gitops, so it can be run anytime.`,
		Aliases: []string{"boot"},
		RunE: func(cmd *cobra.Command, args []string) error {
			return kube.Bootstrap()
		},
	}
	return &cmd
}
