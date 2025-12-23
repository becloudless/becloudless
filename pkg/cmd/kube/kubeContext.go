package kube

import (
	"fmt"

	"github.com/becloudless/becloudless/pkg/kube"
	"github.com/spf13/cobra"
)

func context() *cobra.Command {
	cmd := cobra.Command{
		Use:     "context",
		Aliases: []string{"ctx"},
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
