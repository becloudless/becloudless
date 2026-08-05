package disks

import "github.com/spf13/cobra"

func NixosHardwareDisksCmd() *cobra.Command {
	cmd := &cobra.Command{
		Use:     "disks",
		Aliases: []string{"disk"},
		Short:   "hardware related commands",
	}
	cmd.AddCommand(
		nixosHardwareDisksInfoCmd(),
	)

	return cmd
}
