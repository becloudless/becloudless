//go:build build

package main

import (
	"fmt"
	"io"
	"io/fs"
	"os"
	"path/filepath"
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
			Upx:           gomake.True,
			PostReleaseHook: func(release gomake.StepRelease) error {
				//release.Version
				//send somewhere
				return nil
			},
		}).
		WithStep(&VersionStep{}).
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
