package repository

import (
	"github.com/spf13/cobra"
)

func repositoryAddCmd() *cobra.Command {
	cmd := &cobra.Command{
		Use:   "add",
		Short: "Add something to the infrastructure repository",
	}
	cmd.AddCommand(
		repositoryAddNixosCmd(),
	)
	return cmd
}

func repositoryAddNixosCmd() *cobra.Command {
	cmd := &cobra.Command{
		Use:     "nixos",
		Aliases: []string{"nix"},
		Short:   "Add nixos resources to the infrastructure repository",
	}
	cmd.AddCommand(
		repositoryAddNixosSystemCmd(),
		repositoryAddNixosGroupCmd(),
	)
	return cmd
}
