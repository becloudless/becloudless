package nixos

import (
	"github.com/spf13/cobra"
)

func nixosIsoCmd() *cobra.Command {
	cmd := &cobra.Command{
		Use:   "iso",
		Short: "Build iso image to boot device to install",
		RunE: func(cmd *cobra.Command, args []string) error {
			return nil
		},
	}
	return cmd
}
