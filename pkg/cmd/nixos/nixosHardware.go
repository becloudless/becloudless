package nixos

import "github.com/spf13/cobra"

func nixosHardwareCmd() *cobra.Command {
	cmd := &cobra.Command{
		Use:   "hardware",
		Short: "hardware related commands",
	}
	cmd.AddCommand(
		nixosHardwareConfigCmd(),
		nixosHardwareNetworkDriverCmd(),
	)
	return cmd
}
