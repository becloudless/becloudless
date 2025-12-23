package kube

import (
	"github.com/becloudless/becloudless/pkg/kube"
	"github.com/spf13/cobra"
)

func bootstrap() *cobra.Command {
	cmd := cobra.Command{
		Use:     "bootstrap",
		Aliases: []string{"boot"},
		RunE: func(cmd *cobra.Command, args []string) error {
			return kube.Bootstrap()
		},
	}
	return &cmd
}
