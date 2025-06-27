package cmd

import (
	"github.com/n0rad/go-erlog/logs"
	"github.com/spf13/cobra"
	"os"
	"path/filepath"
)

// HandleResult must exit the program and should be the only one doing so
func HandleResult(err error) {
	if err != nil {
		logs.WithE(err).Fatal("Command failed")
	}
	os.Exit(0)
}

func RootCmd(args []string) *cobra.Command {
	cmd := &cobra.Command{
		SilenceErrors: true,
		SilenceUsage:  true,
		Use:           filepath.Base(args[0]),
	}
	return cmd
}
