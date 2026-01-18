package ci

import (
	"fmt"

	"github.com/becloudless/becloudless/pkg/git"
	"github.com/spf13/cobra"
)

func CiDockerCmd() *cobra.Command {
	var gitRef string

	cmd := &cobra.Command{
		Use:   "docker",
		Short: "Handle docker",
		RunE: func(cmd *cobra.Command, args []string) error {
			repo, err := git.OpenRepository(".")
			if err != nil {
				return err
			}

			changes, err := repo.GetFilesChangedInCurrentBranch()
			if err != nil {
				return err
			}

			for s, changeType := range changes {
				fmt.Printf("%s: %s\n", changeType, s)
			}

			return nil
		},
	}

	cmd.Flags().StringVar(&gitRef, "git-ref", "", "Specify a git ref (branch, tag, commit) to build from, when --git is set")

	return cmd
}
