////go:build build

package main

import (
	"io"
	"io/fs"
	"os"
	"path/filepath"
	"strings"

	bclVersion "github.com/becloudless/becloudless/pkg/version"
	"github.com/n0rad/go-erlog/errs"
	"github.com/n0rad/gomake"
)

func version() (string, error) {
	return bclVersion.GenerateIncrementalVersion(0, ".")
}

func main() {
	gomake.ProjectBuilder().
		WithName("bcl").
		WithVersionFunc(version).
		WithStep(&gomake.StepBuild{
			Version: "0.0.0",
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
			OsArchRelease: []string{"linux-amd64", "linux-arm64", "darwin-arm64"},
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
		if skip, skipDir := skipFromAssets(rel, d); skip {
			if skipDir {
				return filepath.SkipDir
			}
			return nil
		}
		target := filepath.Join(dst, rel)
		if d.IsDir() {
			return os.MkdirAll(target, 0755)
		}
		return copyFile(path, target)
	})
}

// skipFromAssets tells if a file of the kube folder must not be embedded in the binary.
// The chart build tooling is not needed to render a chart, and Go ignores the files of a folder having its own go.mod
// (the base chart is its own module) while it would compile the other Go sources as part of the cli module.
func skipFromAssets(rel string, d fs.DirEntry) (skip bool, skipDir bool) {
	if d.IsDir() {
		if ok, _ := filepath.Match("charts/*/build", rel); ok {
			return true, true
		}
		return false, false
	}

	name := d.Name()
	switch name {
	case "go.mod", "go.sum", "build.sh":
		return true, false
	}
	return strings.HasSuffix(name, ".go"), false
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
