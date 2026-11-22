package nixos

import (
	"github.com/becloudless/becloudless/pkg/bcl"
	"github.com/becloudless/becloudless/pkg/cmd/flags"
	repositorynixos "github.com/becloudless/becloudless/pkg/repository/nixos"
	"github.com/becloudless/becloudless/pkg/system/runner"
	"github.com/n0rad/go-erlog/errs"
	"github.com/n0rad/go-erlog/logs"
	"github.com/n0rad/memguarded"
	"github.com/spf13/cobra"
)

func nixosHardwareCreateCmd() *cobra.Command {
	sshConfig := runner.SshConnectionConfig{
		Password: memguarded.NewService(),
	}

	cmd := &cobra.Command{
		Use:   "create [name]",
		Short: "Create a nixos hardware module in the infrastructure repository",
		Long: "Creates nixos/modules/nixos/hardware/<name>/default.nix in the infrastructure repository of the current directory. " +
			"With --host, the kernel modules and the commons are deduced from that machine, and the name defaults to its product name. " +
			"Without --host, an empty hardware module is created. An existing hardware is never overwritten.",
		Args: cobra.MaximumNArgs(1),
		RunE: func(cmd *cobra.Command, args []string) error {
			infra, err := bcl.FindInfraFromPath(".")
			if err != nil {
				return err
			}

			options := repositorynixos.AddHardwareOptions{InfraDirectory: infra.GetRootDir()}
			if len(args) == 1 {
				options.Name = args[0]
			}

			if sshConfig.Host != "" {
				sshRun, err := runner.NewSshRunner(&sshConfig)
				if err != nil {
					return errs.WithE(err, "Failed to connect to remote host")
				}
				if options.Profile, err = repositorynixos.DetectHardwareProfile(sshRun); err != nil {
					return err
				}
				if options.Name == "" {
					if options.Name, err = repositorynixos.DetectHardwareName(sshRun); err != nil {
						return err
					}
				}
			}
			if options.Name == "" {
				return errs.With("A hardware name is required when no host is given")
			}

			hardwareFile, err := repositorynixos.AddHardware(options)
			if err != nil {
				return err
			}

			logs.WithField("path", hardwareFile).Info("Hardware created")
			logs.Info("Add the new file to git, flakes ignore untracked files")
			return nil
		},
	}

	flags.WithSSHRemoteFlags(cmd, &sshConfig)
	return cmd
}
