package nixos

import (
	"github.com/spf13/cobra"
)

func nixosGroupCreateCmd() *cobra.Command {
	cmd := &cobra.Command{
		Use:   "create",
		Short: "create group",
		Args:  cobra.ExactArgs(1),
		RunE: func(cmd *cobra.Command, args []string) error {
			return nil
			//return nixos.CreateGroup(args[0])
		},
	}
	return cmd
}
