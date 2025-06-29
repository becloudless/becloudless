package cmd

import "github.com/spf13/cobra"

func WebCmd() *cobra.Command {

	cmd := &cobra.Command{
		Use: "web",
		RunE: func(cmd *cobra.Command, args []string) error {
			return nil
		},
	}
	return cmd
}
