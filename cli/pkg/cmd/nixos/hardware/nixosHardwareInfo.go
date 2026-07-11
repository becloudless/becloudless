package hardware

import (
	"encoding/json"
	"fmt"

	"github.com/becloudless/becloudless/pkg/cmd/flags"
	"github.com/becloudless/becloudless/pkg/nixos"
	"github.com/becloudless/becloudless/pkg/system"
	"github.com/becloudless/becloudless/pkg/system/runner"
	"github.com/n0rad/go-erlog/errs"
	"github.com/n0rad/memguarded"
	"github.com/spf13/cobra"
)

func nixosHardwareInfoCmd() *cobra.Command {

	sshConfig := runner.SshConnectionConfig{
		Password: memguarded.NewService(),
	}

	cmd := &cobra.Command{
		Use:   "info",
		Short: "dump system info as json",
		RunE: func(cmd *cobra.Command, args []string) error {
			run := runner.Runner(runner.NewLocalRunner())
			if sshConfig.Host != "" {
				sshRun, err := runner.NewSshRunner(&sshConfig)
				if err != nil {
					return err
				}
				run = sshRun
			}

			sys := system.System{
				SudoRunner: runner.NewShellRunner(run),
			}

			info, err := nixos.ExtractSystemInfo(sys)
			if err != nil {
				return errs.WithE(err, "Failed to extract system info")
			}

			out, err := json.MarshalIndent(info, "", "  ")
			if err != nil {
				return errs.WithE(err, "Failed to marshal system info")
			}

			fmt.Println(string(out))
			return nil
		},
	}

	flags.WithSSHRemoteFlags(cmd, &sshConfig)

	return cmd
}
