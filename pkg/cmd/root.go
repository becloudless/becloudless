package cmd

import (
	"os"
	"path/filepath"

	"github.com/becloudless/becloudless/pkg/bcl"
	"github.com/becloudless/becloudless/pkg/cmd/docker"
	"github.com/becloudless/becloudless/pkg/cmd/nixos"
	"github.com/becloudless/becloudless/pkg/cmd/utils"
	"github.com/becloudless/becloudless/pkg/cmd/version"
	"github.com/n0rad/go-erlog/logs"
	"github.com/spf13/cobra"
)

func RootCmd() *cobra.Command {
	var logLevel string
	var home string

	cmd := &cobra.Command{
		SilenceErrors: true,
		SilenceUsage:  true,
		Use:           filepath.Base(os.Args[0]),
		PersistentPreRunE: func(cmd *cobra.Command, args []string) error {
			if level, err := logs.ParseLevel(logLevel); err != nil {
				logs.WithField("value", logLevel).Fatal("Unknown log level") // TODO fatal
			} else {
				logs.SetLevel(level)
			}

			return bcl.BCL.Init(home)
		},
	}

	cmd.AddCommand(
		docker.DockerCmd(),
		version.VersionCmd(),
		nixos.NixosCmd(),
		utils.UtilsCmd(),
		WebCmd(),
	)

	// Unset the -h help, useful for 'host' arguments
	cmd.PersistentFlags().BoolP("help", "", false, "help for this command")

	cmd.PersistentFlags().StringVarP(&logLevel, "log-level", "L", "info", "Set log level")
	cmd.PersistentFlags().StringVarP(&home, "home", "H", bcl.BCL.App.DefaultHomeFolder(), "bcl home directory")
	return cmd
}
