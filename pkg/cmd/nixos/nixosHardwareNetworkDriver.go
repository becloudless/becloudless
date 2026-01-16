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
			run := runner.NewLocalRunner()
			nixRun := runner.NewNixShellRunner(run, "lshw")
			shellNixRun := runner.NewShellRunner(nixRun)
			return shellNixRun.ExecCmd("lshw -C network | grep -Poh 'driver=[[:alnum:]]+'")
		},
	}
	return cmd
}
