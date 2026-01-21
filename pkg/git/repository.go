package git

import (
	"os"
	"strings"

	"github.com/go-git/go-git/v6"
	"github.com/go-git/go-git/v6/plumbing"
	"github.com/n0rad/go-erlog/data"
	"github.com/n0rad/go-erlog/errs"
	"github.com/n0rad/go-erlog/logs"
)

type Repository struct {
	Root    string
	Repo    *git.Repository
	logData data.Fields
}

func CloneRepository(path string, url string) (*Repository, error) {
	field := data.WithField("path", path).WithField("repo", url)

	if err := os.MkdirAll(path, 0755); err != nil {
		return nil, errs.WithEF(err, data.WithField("path", path), "Failed to create folder to clone git repository")
	}

	logs.WithField("url", url).Info("Cloning repository...")
	repo, err := git.PlainClone(path, &git.CloneOptions{
		URL: url,
	})
	if err != nil {
		return nil, errs.WithEF(err, field, "Failed to clone git repository")
	}

	return &Repository{
		Root:    path,
		Repo:    repo,
		logData: field,
	}, nil
}

func InitRepository(path string) (*Repository, error) {
	field := data.WithField("path", path)
	repo, err := git.PlainInit(path, false)
	if err != nil {
		return nil, errs.WithEF(err, field, "Failed to init repository")
	}
	return &Repository{
		path,
		repo,
		field,
	}, nil
}

func OpenRepository(path string) (*Repository, error) {
	field := data.WithField("path", path)
	repo, err := git.PlainOpenWithOptions(path, &git.PlainOpenOptions{DetectDotGit: true})
	if err != nil {
		return nil, errs.WithEF(err, field, "Failed to open git repository")
	}

	wt, err := repo.Worktree()
	if err != nil {
		return nil, errs.WithE(err, "Failed to open git workree")
	}

	return &Repository{
		wt.Filesystem.Root(),
		repo,
		field,
	}, nil
}

func (r Repository) AddAll() error {
	w, err := r.Repo.Worktree()
	if err != nil {
		return errs.WithE(err, "Failed to git worktree to commit")
	}
	if _, err := w.Add(""); err != nil {
		return errs.WithE(err, "Failed to add files to git")
	}
	return nil
}

// /////////////////////////
func (r Repository) HeadCommitHash(short bool) (string, error) {
	head, err := r.Repo.Head()
	if err != nil {
		return "", errs.WithE(err, "Failed to get repo head")
	}

	if short {
		return r.getShortHash(head.Hash()), nil
	}
	return head.Hash().String(), nil
}

func (r Repository) getShortHash(hash plumbing.Hash) string {
	return hash.String()[0:7]

	// TODO this is slow
	//for i := 7; i < hash.Size(); i++ {
	//	shortHash := hash.String()[0:i]
	//	if !r.hasDuplicateShortHash(shortHash) {
	//		return shortHash
	//	}
	//}
	//return ""
}

func (r Repository) hasDuplicateShortHash(shortHash string) bool {
	blobs, err := r.Repo.CommitObjects()
	if err != nil {
		return true
	}
	count := 0
	for {
		blob, err := blobs.Next()
		if err != nil {
			break
		}
		if strings.HasPrefix(blob.Hash.String(), shortHash) {
			count++
		}
	}
	return count > 1
}

// refs/tags/v42.42
func (r Repository) Checkout(ref string) error {
	wt, err := r.Repo.Worktree()
	if err != nil {
		return errs.WithEF(err, r.logData, "Cannot get repository worktree")
	}
	if err := wt.Checkout(&git.CheckoutOptions{Branch: plumbing.ReferenceName(ref)}); err != nil {
		return errs.WithEF(err, r.logData.WithField("ref", ref), "Failed to checkout reference")
	}
	return nil
}

func (r Repository) GetRemoteOriginURL() (string, error) {
	remote, err := r.Repo.Remote("origin")
	if err != nil {
		return "", errs.WithEF(err, r.logData.WithField("remote", "origin"), "Failed to get git remote")
	}

	cfg := remote.Config()
	if cfg == nil || len(cfg.URLs) == 0 {
		return "", errs.WithEF(nil, r.logData.WithField("remote", "origin"), "Git remote origin has no URL configured")
	}
	return cfg.URLs[0], nil
}
