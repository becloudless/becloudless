package repository

import (
	"github.com/becloudless/becloudless/pkg/cmd/repository/nixos"
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
		nixos.NixosCmd(),
	)
	return cmd
}
