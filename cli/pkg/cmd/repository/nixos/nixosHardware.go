package nixos

import (
	"github.com/spf13/cobra"
)

func nixosHardwareCmd() *cobra.Command {
	cmd := &cobra.Command{
		Use:     "hardware",
		Aliases: []string{"hw"},
		Short:   "Handle the nixos hardware modules of the infrastructure repository",
	}
	cmd.AddCommand(
		nixosHardwareCreateCmd(),
	)
	return cmd
}
