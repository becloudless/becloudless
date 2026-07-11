package nixos

import (
	"github.com/becloudless/becloudless/pkg/cmd/nixos/hardware"
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
		hardware.NixosHardwareCmd(),
		nixosUpgradeCmd(),
	)
	return cmd
}
