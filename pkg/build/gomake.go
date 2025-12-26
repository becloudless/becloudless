//go:build build

package main

import (
	"fmt"
	"strings"
	"time"

	"github.com/n0rad/go-erlog/errs"
	"github.com/n0rad/gomake"
)

func main() {
	gomake.ProjectBuilder().
		WithName("bcl").
		WithVersionFunc(func() (string, error) {
			now := time.Now()
			gitHash, err := gomake.ExecGetStdout("git", "rev-parse", "--short", "HEAD")
			if err != nil {
				return "", errs.WithE(err, "Failed to get git commit hash")
			}
			hms := strings.TrimLeft(now.Format("1504"), "0")
			if hms == "" {
				hms = "0"
			}
			return fmt.Sprintf("%s.%s.%s-H%s", "0", now.Format("060102"), hms, gitHash), nil
		}).
		WithStep(&gomake.StepBuild{
			PreBuildHook: func(build gomake.StepBuild) error {
				if err := gomake.EnsureTool("go-jsonschema", "github.com/atombender/go-jsonschema"); err != nil {
					return err
				}

				return gomake.ExecShell("go generate ./...")
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
		MustBuild().MustExecute()
}
