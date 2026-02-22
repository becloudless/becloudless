package kube

import (
	"fmt"

	"github.com/becloudless/becloudless/pkg/kube"
	"github.com/spf13/cobra"
)

func kubeContextCmd() *cobra.Command {
	var aliases bool

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

			if aliases {
				if context.Cluster == "" {
					fmt.Println(`alias k=kubectl`)
					fmt.Println(`unalias stern 2>/dev/null`)
					fmt.Println(`unalias k9s 2>/dev/null`)
				} else if context.Namespace == "" {
					fmt.Println(`alias k=kubectl`)
					fmt.Println(`unalias stern 2>/dev/null`)
					fmt.Println(`unalias k9s 2>/dev/null`)
				} else {
					fmt.Printf("alias k='kubectl -n %s'\n", context.Namespace)
					fmt.Printf("alias stern='stern -n %s'\n", context.Namespace)
					fmt.Printf("alias k9s='k9s -n %s'\n", context.Namespace)
				}
			}
			return nil
		},
	}

	cmd.Flags().BoolVarP(&aliases, "aliases", "a", true, "Alias k, stern and k9s to current context")

	return &cmd
}
