package bcl

import (
	"os"
	"path"

	"github.com/becloudless/becloudless/pkg/security"
	"github.com/n0rad/go-app"
	"github.com/n0rad/go-erlog/data"
	"github.com/n0rad/go-erlog/errs"
	"github.com/n0rad/go-erlog/logs"
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
	app.App
	//Infra string `yaml:"repository,omitempty"`
	//
	//Repo *git.Infra
}

func (bcl *Bcl) Init(home string) error {
	if err := bcl.App.Init(home, bcl); err != nil {
		return err
	}

	//if bcl.Infra == "" {
	//	bcl.Infra = path.Join(bcl.Home, pathRepository)
	//}
	//if _, err := os.Stat(bcl.Infra); os.IsNotExist(err) {
	//	logs.WithField("path", bcl.Infra).Warn("git repository does not exists, creating")
	//	repository, err := git.InitRepository(bcl.Infra)
	//	if err != nil {
	//		return errs.WithE(err, "Failed to init git repository")
	//	}
	//	bcl.Repo = repository
	//} else if err != nil {
	//	return errs.WithEF(err, data.WithField("path", bcl.Infra), "Failed to read git repository")
	//} else {
	//	repository, err := git.OpenRepository(bcl.Infra)
	//	if err != nil {
	//		return errs.WithEF(err, data.WithField("path", bcl.Infra), "Failed to open git repository")
	//	}
	//	bcl.Repo = repository
	//}

	//if err := bcl.ensureNixos(); err != nil {
	//	return err
	//}

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
