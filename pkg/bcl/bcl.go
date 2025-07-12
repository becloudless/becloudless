package bcl

import (
	"filippo.io/age"
	"github.com/becloudless/becloudless/pkg/bcl/app"
	"github.com/becloudless/becloudless/pkg/git"
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
const pathSecrets = "secrets"
const pathAgeKeyFile = "key"
const pathAgePublicKeyFile = "key.pub"

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

	if err := bcl.ensureAgeKey(); err != nil {
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

func (bcl *Bcl) ensureAgeKey() error {
	secretsFolder := path.Join(bcl.Home, pathSecrets)
	if stat, err := os.Stat(secretsFolder); os.IsNotExist(err) {
		if err := os.MkdirAll(secretsFolder, 0700); err != nil {
			return errs.WithEF(err, data.WithField("folder", secretsFolder), "Failed to create secret folder")
		}
	} else if err != nil {
		return errs.WithEF(err, data.WithField("folder", secretsFolder), "Failed to read secret folder")
	} else {
		if stat.Mode().Perm() != 0700 {
			if err := os.Chmod(secretsFolder, 0700); err != nil {
				return errs.WithE(err, "Secrets folder have wrong mode (0700) and cannot be changed")
			}
			logs.WithField("folder", secretsFolder).
				WithField("expected", "0700").
				WithField("current", stat.Mode().String()).
				Warn("Secrets folder had wrong mode. It's fixed")
		}
	}

	ageKeyfile := path.Join(secretsFolder, pathAgeKeyFile)
	if stat, err := os.Stat(ageKeyfile); os.IsNotExist(err) {
		logs.WithField("file", ageKeyfile).Warn("Age private key is missing, creating... This file contain the private key to access all secrets in bcl and should be backup")
		identity, err := age.GenerateX25519Identity()
		if err != nil {
			return errs.WithE(err, "Failed to generate new age key")
		}
		if err := os.WriteFile(ageKeyfile, []byte(identity.String()), 0600); err != nil {
			return errs.WithEF(err, data.WithField("file", ageKeyfile), "Failed to write age key file")
		}
	} else if err != nil {
		return errs.WithEF(err, data.WithField("file", ageKeyfile), "Failed to read age key file")
	} else {
		if stat.Mode().Perm() != 0600 {
			if err := os.Chmod(secretsFolder, 0600); err != nil {
				return errs.WithEF(err, data.WithField("file", ageKeyfile), "age key file have wrong mode (0700) and cannot be changed")
			}
			logs.WithField("folder", secretsFolder).
				WithField("expected", "0700").
				WithField("current", stat.Mode().String()).
				Warn("Secrets age file had wrong mode. It's fixed")
		}
	}

	agePublicKeyfile := path.Join(secretsFolder, pathAgePublicKeyFile)
	if stat, err := os.Stat(agePublicKeyfile); os.IsNotExist(err) || (err == nil && stat.Size() == 0) {
		logs.WithField("file", agePublicKeyfile).Warn("Age public is missing, creating...")
		file, err := os.Open(ageKeyfile)
		if err != nil {
			return errs.WithE(err, "Failed to read age private key to generate public key")
		}
		ids, err := age.ParseIdentities(file)

		openFile, err := os.OpenFile(agePublicKeyfile, os.O_WRONLY|os.O_CREATE|os.O_EXCL, 0666)
		if err != nil {
			return errs.WithEF(err, data.WithField("file", agePublicKeyfile), "Failed to open age public key file")
		}
		for _, id := range ids {
			id, ok := id.(*age.X25519Identity)
			if !ok {
				return errs.WithF(data.WithField("id", id), "Unexpected age identity")
			}
			if _, err := openFile.Write([]byte(id.Recipient().String() + "\n")); err != nil {
				return errs.WithE(err, "Failed to write age public key to file")
			}
		}
	} else if err != nil {
		return errs.WithEF(err, data.WithField("file", agePublicKeyfile), "Failed to read age public key file")
	}
	return nil
}
