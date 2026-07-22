package nixos

import (
	"github.com/becloudless/becloudless/pkg/cmd/nixos/backup"
	"github.com/spf13/cobra"
)

func NixosCmd() *cobra.Command {
	cmd := &cobra.Command{
		Use:     "nixos",
		Aliases: []string{"nix"},
		Short:   "Handle devices with Nix Operating System",
	}
	cmd.AddCommand(
		nixosInstallCmd(),
		nixosIsoCmd(),
		nixosPrepareCmd(),
		nixosGroupCmd(),
		nixosGlobalCmd(),
		nixosHardwareCmd(),
		nixosUpgradeCmd(),
		backup.NixosBackupCmd(),
	)
	return cmd
}
