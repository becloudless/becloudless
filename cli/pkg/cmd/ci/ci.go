package ci

import (
	"github.com/spf13/cobra"
)

func CiCmd() *cobra.Command {
	cmd := &cobra.Command{
		Use:   "ci",
		Short: "Handle ci",
	}
	cmd.AddCommand(
		CiDockerCmd())
	return cmd
}
