package ci

import (
	"os"
	"path/filepath"
	"strings"

	"github.com/becloudless/becloudless/pkg/cmd/docker"
	"github.com/becloudless/becloudless/pkg/git"
	"github.com/n0rad/go-erlog/data"
	"github.com/n0rad/go-erlog/errs"
	"github.com/n0rad/go-erlog/logs"
	"github.com/spf13/cobra"
)

func CiDockerCmd() *cobra.Command {
	//var gitRef string

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

			toBuild := make(map[string]struct{})

			for s, changeType := range changes {
				if !strings.HasPrefix(s, "dockerfiles/") {
					continue
				}

				if changeType == git.ChangeDeleted {
					continue
				}

				file, err := findDockerfileFolderFromFile(s)
				if err != nil {
					return errs.WithEF(err, data.WithField("file", s), "Failed to find dockerfile folder from file")
				}

				toBuild[file] = struct{}{}
			}

			for path, _ := range toBuild {
				logs.WithField("path", path).Info("Building docker image")

				config := docker.BuildConfig{
					DockerfilePath: path,
				}
				if err := config.Init(); err != nil {
					return err
				}
				if err := docker.DockerBuildx(config); err != nil {
					return err
				}
			}

			return nil
		},
	}

	//cmd.Flags().StringVar(&gitRef, "git-ref", "", "Specify a git ref (branch, tag, commit) to build from")

	return cmd
}

func findDockerfileFolderFromFile(path string) (string, error) {
	if path == "" {
		return "", nil
	}

	if filepath.Base(path) == "Dockerfile" {
		return filepath.Dir(path), nil
	}

	// Normalize and drop the file portion
	dir := filepath.Dir(path)

	for {
		candidate := filepath.Join(dir, "Dockerfile")
		if _, err := os.Stat(candidate); err == nil {
			return dir, nil
		}

		parent := filepath.Dir(dir)
		if parent == dir || dir == "." || dir == string(filepath.Separator) {
			break
		}
		dir = parent
	}

	return "", nil
}
