////go:build build

package main

import (
	"io"
	"io/fs"
	"os"
	"path/filepath"

	bclVersion "github.com/becloudless/becloudless/pkg/version"
	"github.com/n0rad/go-erlog/errs"
	"github.com/n0rad/gomake"
)

func version() (string, error) {
	return bclVersion.GenerateVersion(0), nil
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
				// copy kube root folder to assets
				if err := copyDir("../kube", "assets/kube"); err != nil {
					return errs.WithE(err, "Failed to copy kube folder to assets")
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
		MustBuild().MustExecute()
}

func copyDir(src, dst string) error {
	if err := os.RemoveAll(dst); err != nil {
		return errs.WithE(err, "Failed to remove destination directory")
	}
	return filepath.WalkDir(src, func(path string, d fs.DirEntry, err error) error {
		if err != nil {
			return err
		}
		rel, err := filepath.Rel(src, path)
		if err != nil {
			return err
		}
		target := filepath.Join(dst, rel)
		if d.IsDir() {
			return os.MkdirAll(target, 0755)
		}
		return copyFile(path, target)
	})
}

func copyFile(src, dst string) error {
	in, err := os.Open(src)
	if err != nil {
		return err
	}
	defer in.Close()

	out, err := os.Create(dst)
	if err != nil {
		return err
	}
	defer out.Close()

	_, err = io.Copy(out, in)
	return err
}
