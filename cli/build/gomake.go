//go:build build

package main

import (
	"os"

	"github.com/n0rad/gomake"
)

func main() {
	gomake.ProjectBuilder().
		WithName("bcl").
		WithStep(&gomake.StepClean{
			PostCleanHook: func(clean gomake.StepClean) error {
				if err := os.MkdirAll("dist/", 0777); err != nil {
					return err
				}
				if err := os.WriteFile("dist/dummy.go", []byte("package dist\n"), 0644); err != nil {
					return err
				}

				return nil
			},
		}).WithStep(&gomake.StepBuild{
		PreBuildHook: func(build gomake.StepBuild) error {
			//if err := gomake.ExecShell("git update-index --skip-worktree pkg/bcl/changelog/CHANGELOG.md "); err != nil {
			//	return err
			//}

			return gomake.ExecShell("go generate ./...")
		},
	}).
		WithStep(&gomake.StepRelease{
			GithubRelease: false,
			OsArchRelease: []string{"linux-amd64", "darwin-amd64", "linux-arm64", "darwin-arm64"},
			PostReleaseHook: func(release gomake.StepRelease) error {
				//release.Version
				//send somewhere
				return nil
			},
		}).
		MustBuild().MustExecute()
}
