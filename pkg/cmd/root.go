package cmd

import (
	"github.com/becloudless/becloudless/pkg/bcl"
	"github.com/n0rad/go-erlog/logs"
	"github.com/spf13/cobra"
	"os"
	"path/filepath"
)

func RootCmd() *cobra.Command {
	var logLevel string
	var home string

	cmd := &cobra.Command{
		SilenceErrors: true,
		SilenceUsage:  true,
		Use:           filepath.Base(os.Args[0]),
		PersistentPreRunE: func(cmd *cobra.Command, args []string) error {
			if logLevel != "" {
				level, err := logs.ParseLevel(logLevel)
				if err != nil {
					logs.WithField("value", logLevel).Fatal("Unknown log level")
				}
				logs.SetLevel(level)
			}
			return bcl.BCL.Init(home)
		},
	}

	cmd.AddCommand(
		VersionCmd(),
		WebCmd(),
		NixCmd(),
	)

	// Remove the -h help shorthand, as gitlab auth login uses it for hostname
	cmd.PersistentFlags().BoolP("help", "", false, "help for this command")

	cmd.PersistentFlags().StringVarP(&logLevel, "log-level", "L", "", "Set log level")
	cmd.PersistentFlags().StringVarP(&home, "home", "H", bcl.BCL.App.DefaultHomeFolder(), "bcl home directory")
	return cmd
}
