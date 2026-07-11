package hardware

import "github.com/spf13/cobra"

func NixosHardwareCmd() *cobra.Command {
	cmd := &cobra.Command{
		Use:   "hardware",
		Short: "hardware related commands",
	}
	cmd.AddCommand(
		nixosHardwareConfigCmd(),
		nixosHardwareNetworkDriverCmd(),
		nixosHardwareInfoCmd(),
	)
	return cmd
}
