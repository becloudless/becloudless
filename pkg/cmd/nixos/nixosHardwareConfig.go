package nixos

import (
	"github.com/becloudless/becloudless/pkg/system/runner"
	"github.com/spf13/cobra"
)

func nixosHardwareConfigCmd() *cobra.Command {
	cmd := &cobra.Command{
		Use:   "config",
		Short: "hardware related commands",
		Long:  "Generate hardware configuration for NixOS.",
		RunE: func(cmd *cobra.Command, args []string) error {
			run := runner.NewLocalRunner()
			return run.ExecCmd("nixos-generate-config", "--no-filesystems", "--show-hardware-config")
		},
	}
	return cmd
}
