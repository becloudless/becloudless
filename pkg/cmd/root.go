package cmd

import (
	"github.com/becloudless/becloudless/pkg/bcl"
	"github.com/spf13/cobra"
	"log/slog"
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
		PreRunE: func(cmd *cobra.Command, args []string) error {
			if logLevel != "" {
				var level slog.Level
				err := level.UnmarshalText([]byte(logLevel))
				if err != nil {
					slog.With("content", logLevel).Error("Unknown log level")
					return err
				}
				slog.SetLogLoggerLevel(level)
			}

			bcl.BCL.Home = home
			return nil
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
