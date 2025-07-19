package bcl

import (
	"github.com/becloudless/becloudless/pkg/bcl/app"
	"github.com/becloudless/becloudless/pkg/git"
	"github.com/becloudless/becloudless/pkg/security"
	"github.com/becloudless/becloudless/pkg/utils"
	"github.com/n0rad/go-erlog/data"
	"github.com/n0rad/go-erlog/errs"
	"github.com/n0rad/go-erlog/logs"
	"os"
	"path"
)

// BCL is the global app instance
var BCL Bcl

const pathRepository = "repository"
const PathSecrets = "secrets"
const PathEd25519KeyFile = "ed25519"

func init() {
	BCL.App.Name = "bcl"
}

type Bcl struct {
	Repository *git.Repository
	app.App
}

func (bcl *Bcl) Init(home string) error {
	bcl.Home = home
	if err := bcl.PrepareHome(); err != nil {
		return err
	}

	repositoryPath := path.Join(bcl.Home, pathRepository)
	if _, err := os.Stat(repositoryPath); os.IsNotExist(err) {
		logs.WithField("path", repositoryPath).Warn("git repository does not exists, creating")
		repository, err := git.InitRepository(repositoryPath)
		if err != nil {
			return errs.WithE(err, "Failed to init git repository")
		}
		bcl.Repository = repository
	} else if err != nil {
		return errs.WithEF(err, data.WithField("path", repositoryPath), "Failed to read git repository")
	} else {
		repository, err := git.OpenRepository(repositoryPath)
		if err != nil {
			return errs.WithEF(err, data.WithField("path", repositoryPath), "Failed to open git repository")
		}
		bcl.Repository = repository
	}

	if err := bcl.ensureNixos(); err != nil {
		return err
	}

	secretFolder := path.Join(bcl.Home, PathSecrets)
	// folder
	if stat, err := os.Stat(secretFolder); os.IsNotExist(err) {
		if err := os.MkdirAll(secretFolder, 0700); err != nil {
			return errs.WithEF(err, data.WithField("folder", secretFolder), "Failed to create key folder")
		}
	} else if err != nil {
		return errs.WithEF(err, data.WithField("folder", secretFolder), "Failed to read key folder")
	} else {
		if stat.Mode().Perm() != 0700 {
			if err := os.Chmod(secretFolder, 0700); err != nil {
				return errs.WithE(err, "Key folder have wrong mode (0700) and cannot be changed")
			}
			logs.WithField("folder", secretFolder).
				WithField("expected", "0700").
				WithField("current", stat.Mode().String()).
				Warn("Key folder had wrong mode. It's fixed")
		}
	}

	if err := security.EnsureEd25519KeyFile(path.Join(secretFolder, PathEd25519KeyFile)); err != nil {
		return err
	}

	//TODO commit?

	return nil
}

func (bcl *Bcl) ensureNixos() error {
	flakePath := path.Join(bcl.Repository.Root, "nixos", "flake.nix")
	if _, err := os.Stat(flakePath); os.IsNotExist(err) {
		logs.WithE(err).WithField("path", flakePath).Warn("flake does not exists, creating")

		if err := os.MkdirAll(path.Dir(flakePath), 0755); err != nil {
			return errs.WithE(err, "Failed to create nixos directory")
		}

		if err := utils.CopyFile(path.Join(bcl.AssetsPath, "repository", "nixos", "flake.nix"),
			path.Join(bcl.Repository.Root, "nixos", "flake.nix")); err != nil {
			return errs.WithE(err, "Failed to copy default flake.nix")
		}

		if err := bcl.Repository.AddAll(); err != nil {
			return errs.WithE(err, "Failed to add new files to git")
		}
	}
	return nil
}
