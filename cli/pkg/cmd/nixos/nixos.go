package nixos

import (
	"github.com/becloudless/becloudless/pkg/cmd/nixos/backup"
	"github.com/becloudless/becloudless/pkg/cmd/nixos/hardware"
	"github.com/becloudless/becloudless/pkg/cmd/nixos/iso"
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
		iso.NixosIsoCmd(),
		nixosPrepareCmd(),
		nixosGroupCmd(),
		nixosGlobalCmd(),
		hardware.NixosHardwareCmd(),
		nixosUpgradeCmd(),
		backup.NixosBackupCmd(),
	)
	return cmd
}
