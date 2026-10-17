package ci

import (
	"fmt"
	"os"
	"strings"

	"github.com/becloudless/becloudless/pkg/git"
	"github.com/n0rad/go-erlog/data"
	"github.com/n0rad/go-erlog/errs"
	"github.com/n0rad/go-erlog/logs"
	"github.com/spf13/cobra"
)

func CiChangesCmd() *cobra.Command {
	cmd := &cobra.Command{
		Use:   "changes [path-prefix...]",
		Short: "Tell if files under the given path prefixes changed in the current branch",
		Long: `Tell if files under the given path prefixes changed in the current branch (the last commit on main).
Each argument may contain several newline-separated path prefixes.
Prints "changed=true" or "changed=false", also appended to the file pointed by $GITHUB_OUTPUT when set.`,
		Args: cobra.MinimumNArgs(1),
		RunE: func(cmd *cobra.Command, args []string) error {
			var prefixes []string
			for _, arg := range args {
				for _, line := range strings.Split(arg, "\n") {
					if line = strings.TrimSpace(line); line != "" {
						prefixes = append(prefixes, line)
					}
				}
			}
			if len(prefixes) == 0 {
				return errs.With("No path prefix given")
			}

			repo, err := git.OpenRepository(".")
			if err != nil {
				return err
			}

			changes, err := repo.GetFilesChangedInCurrentBranch()
			if err != nil {
				return err
			}

			logs.WithField("prefixes", prefixes).Info("Path prefixes to check")
			for file, changeType := range changes {
				logs.WithField("file", file).WithField("type", string(changeType)).Info("Changed file")
			}

			changed := false
			for file := range changes {
				for _, prefix := range prefixes {
					if strings.HasPrefix(file, prefix) {
						logs.WithField("file", file).WithField("prefix", prefix).Debug("Change found")
						changed = true
						break
					}
				}
				if changed {
					break
				}
			}

			output := fmt.Sprintf("changed=%t", changed)
			fmt.Println(output)

			if outputFile := os.Getenv("GITHUB_OUTPUT"); outputFile != "" {
				f, err := os.OpenFile(outputFile, os.O_APPEND|os.O_WRONLY|os.O_CREATE, 0644)
				if err != nil {
					return errs.WithEF(err, data.WithField("file", outputFile), "Failed to open GITHUB_OUTPUT file")
				}
				defer f.Close()
				if _, err := f.WriteString(output + "\n"); err != nil {
					return errs.WithEF(err, data.WithField("file", outputFile), "Failed to write GITHUB_OUTPUT file")
				}
			}

			return nil
		},
	}

	return cmd
}
