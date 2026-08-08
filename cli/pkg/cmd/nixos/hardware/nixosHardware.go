package hardware

import (
	"github.com/becloudless/becloudless/pkg/cmd/nixos/hardware/disks"
	"github.com/spf13/cobra"
)

func NixosHardwareCmd() *cobra.Command {
	cmd := &cobra.Command{
		Use:     "hardware",
		Aliases: []string{"hw"},
		Short:   "hardware related commands",
	}
	cmd.AddCommand(
		nixosHardwareConfigCmd(),
		nixosHardwareNetworkDriverCmd(),
		nixosHardwareInfoCmd(),
		disks.NixosHardwareDisksCmd(),
	)
	return cmd
}
