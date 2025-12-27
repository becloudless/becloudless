package bcl

import (
	"os"
	"path"
	"path/filepath"
	"strings"

	"github.com/becloudless/becloudless/pkg/git"
	"github.com/becloudless/becloudless/pkg/utils"
	"github.com/n0rad/go-erlog/data"
	"github.com/n0rad/go-erlog/errs"
	"github.com/n0rad/go-erlog/logs"
)

type Infra struct {
	Git *git.Repository

	rootPath string
}

func FindInfraFromPath(path string) (*Infra, error) {
	repo, err := git.OpenRepository(path)
	if err != nil {
		return nil, err
	}

	pathResolved, err := filepath.Abs(".")
	if err != nil {
		return nil, errs.WithEF(err, data.WithField("path", path), "Failed to get absolute path")
	}

	rel, err := filepath.Rel(repo.Root, pathResolved)
	if err != nil {
		return nil, errs.WithEF(err, data.WithField("path", pathResolved).WithField("git", repo.Root), "Failed to get relative path")
	}

	infraPath := repo.Root
	// find infra path in git repo by looking for nixos/flake.nix related to given path
	for i := strings.Count(rel, "/"); i >= 0; i-- {
		current := filepath.Join(strings.Split(rel, "/")[:i+1]...)
		if _, err := os.Stat(filepath.Join(repo.Root, current, "nixos", "flake.nix")); err == nil {
			infraPath = filepath.Join(repo.Root, current)
			break
		}
	}

	return &Infra{Git: repo, rootPath: infraPath}, nil
}

func (r *Infra) GetNixosDir() string {
	nixosPath := path.Join(r.rootPath, "nixos")
	if nixosPath[0] != '/' && !strings.HasPrefix(nixosPath, "./") {
		nixosPath = "./" + nixosPath
	}
	return nixosPath
}

func (r *Infra) ensureNixos() error {
	flakePath := path.Join(r.rootPath, "nixos", "flake.nix")
	if _, err := os.Stat(flakePath); os.IsNotExist(err) {
		logs.WithE(err).WithField("path", flakePath).Warn("flake does not exists, creating")

		if err := os.MkdirAll(path.Dir(flakePath), 0755); err != nil {
			return errs.WithE(err, "Failed to create nixos directory")
		}

		if err := utils.CopyFile(path.Join(BCL.EmbeddedPath, "assets", "repository", "nixos", "flake.nix"),
			path.Join(r.rootPath, "nixos", "flake.nix")); err != nil {
			return errs.WithE(err, "Failed to copy default flake.nix")
		}

		if err := r.Git.AddAll(); err != nil {
			return errs.WithE(err, "Failed to add new files to git")
		}
	}
	return nil
}
