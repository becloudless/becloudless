package repository

import (
	"github.com/spf13/cobra"
)

func RepositoryCmd() *cobra.Command {
	cmd := &cobra.Command{
		Use:     "repository",
		Aliases: []string{"repo"},
		Short:   "Handle the infrastructure repository",
	}
	cmd.AddCommand(
		repositoryInitCmd(),
		repositoryAddCmd(),
	)
	return cmd
}
