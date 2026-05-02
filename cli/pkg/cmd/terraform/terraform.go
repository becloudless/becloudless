package terraform

import (
	"github.com/spf13/cobra"
)

func TerraformCmd() *cobra.Command {
	cmd := &cobra.Command{
		Use:     "terraform",
		Aliases: []string{"tf"},
		Short:   "Handle terraform",
	}
	cmd.AddCommand(
		terraformPlanCmd(),
		terraformApplyCmd(),
	)
	return cmd
}
