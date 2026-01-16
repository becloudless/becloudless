package nixos

import (
	"github.com/becloudless/becloudless/pkg/system/runner"
	"github.com/spf13/cobra"
)

func nixosHardwareNetworkDriverCmd() *cobra.Command {
	cmd := &cobra.Command{
		Use:   "network-driver",
		Short: "find network driver of current system",
		RunE: func(cmd *cobra.Command, args []string) error {
			nixRunner := runner.NewNixShellRunner(runner.NewLocalRunner(), "lshw")
			return nixRunner.ExecCmd("sh", "-c", "lshw -C network | grep -Poh 'driver=[[:alnum:]]+'")
		},
	}
	return cmd
}

// nix-shell --extra-experimental-features 'nix-command flakes' -p lshw --run 'sh -c "lshw -C network | grep -Poh ''driver=[[:alnum:]]+''"'
