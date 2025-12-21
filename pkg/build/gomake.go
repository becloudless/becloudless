//go:build build

package main

import (
	"fmt"
	"strings"
	"time"

	"github.com/n0rad/gomake"
)

func main() {
	gomake.ProjectBuilder().
		WithName("bcl").
		WithVersionFunc(func() (string, error) {
			now := time.Now()
			hms := strings.TrimLeft(now.Format("1504"), "0")
			if hms == "" {
				hms = "0"
			}
			return fmt.Sprintf("%s.%s.%s", now.Format("06"), now.Format("0102"), hms), nil
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
