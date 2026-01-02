////go:build build

package main

import (
	"fmt"
	"strings"
	"time"

	"github.com/n0rad/go-erlog/errs"
	"github.com/n0rad/gomake"
	"github.com/spf13/cobra"
)

type VersionStep struct {
	project *gomake.Project
}

func (v VersionStep) Name() string {
	return "version"
}

func (v VersionStep) Init(project *gomake.Project) error {
	v.project = project
	return nil
}

func (v VersionStep) GetCommand() *cobra.Command {
	var hash string
	cmd := cobra.Command{
		Use:   "version",
		Short: "Generate version",
		RunE: func(cmd *cobra.Command, args []string) error {
			version, err := versionHash(hash)
			if err != nil {
				return err
			}
			fmt.Println(version)
			return nil
		},
	}

	cmd.Flags().StringVarP(&hash, "hash", "H", "", "the git Hash")

	return &cmd
}

func version() (string, error) {
	gitHash, err := gomake.ExecGetStdout("git", "rev-parse", "--short", "HEAD")
	if err != nil {
		return "", errs.WithE(err, "Failed to get git commit hash")
	}
	return versionHash(gitHash)
}

func versionHash(hash string) (string, error) {
	if hash == "" {
		return version()
	}
	now := time.Now()
	hms := strings.TrimLeft(now.Format("1504"), "0")
	if hms == "" {
		hms = "0"
	}
	return fmt.Sprintf("%s.%s.%s-H%.8s", "0", now.Format("060102"), hms, hash), nil
}

func main() {
	gomake.ProjectBuilder().
		WithName("bcl").
		WithVersionFunc(version).
		WithStep(&gomake.StepBuild{
			PreBuildHook: func(build gomake.StepBuild) error {
				if err := gomake.EnsureTool("go-jsonschema", "github.com/atombender/go-jsonschema"); err != nil {
					return err
				}
				return nil
			},
		}).
		WithStep(&gomake.StepRelease{
			GithubRelease: true,
			DefaultBranch: "main",
			OsArchRelease: []string{"linux-amd64", "darwin-amd64", "linux-arm64", "darwin-arm64"},
			PostReleaseHook: func(release gomake.StepRelease) error {
				//release.Version
				//send somewhere
				return nil
			},
		}).
		WithStep(&VersionStep{}).
		MustBuild().MustExecute()
}
