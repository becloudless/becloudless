package repository

import (
	"github.com/becloudless/becloudless/pkg/bcl"
	"github.com/becloudless/becloudless/pkg/repository"
	"github.com/n0rad/go-erlog/logs"
	"github.com/spf13/cobra"
)

func repositoryAddNixosSystemCmd() *cobra.Command {
	options := repository.AddNixosSystemOptions{}

	cmd := &cobra.Command{
		Use:   "system <name>",
		Short: "Add a nixos system to the infrastructure repository",
		Long:  "Creates nixos/systems/<architecture>/<name>/default.nix in the infrastructure repository of the current directory. An existing system is never overwritten.",
		Args:  cobra.ExactArgs(1),
		RunE: func(cmd *cobra.Command, args []string) error {
			infra, err := bcl.FindInfraFromPath(".")
			if err != nil {
				return err
			}

			options.Name = args[0]
			options.InfraDirectory = infra.GetRootDir()
			systemFile, err := repository.AddNixosSystem(options)
			if err != nil {
				return err
			}

			logs.WithField("path", systemFile).Info("System created")
			logs.Info("Add the new file to git, flakes ignore untracked files")
			return nil
		},
	}

	cmd.Flags().StringVar(&options.Architecture, "architecture", repository.DefaultNixosSystemArchitecture, "System architecture")
	cmd.Flags().StringVar(&options.Group, "group", "", "System group")
	cmd.Flags().StringVar(&options.Hardware, "hardware", "", "Hardware module of the system")
	cmd.Flags().StringSliceVar(&options.Devices, "device", nil, "System disk device, can be repeated")
	cmd.Flags().StringVar(&options.MotherboardUuid, "motherboard-uuid", "", "Motherboard UUID identifying the machine")
	cmd.Flags().StringSliceVar(&options.NetworkMacs, "mac", nil, "Network MAC address identifying the machine, can be repeated")
	_ = cmd.MarkFlagRequired("group")
	return cmd
}
