package kube

import (
	"fmt"

	"github.com/becloudless/becloudless/pkg/kube"
	"github.com/spf13/cobra"
)

func kubeContextCmd() *cobra.Command {
	cmd := cobra.Command{
		Use:     "context",
		Aliases: []string{"ctx"},
		Short:   "Get the CWD kube context information in shell env format to be sourced.",
		RunE: func(cmd *cobra.Command, args []string) error {
			context, err := kube.GetContext(".")
			if err != nil {
				return err
			}
			fmt.Print(context.ToEnv())
			return nil
		},
	}
	return &cmd
}
