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

//
//func (r Repository) HeadCommitHash(short bool) (string, error) {
//	args := []string{"-C", r.repoDir, "rev-parse", "HEAD"}
//	if short {
//		args = append(args, "--short")
//	}
//	stdout, stderr, err := runner.ExecCmdGetStdoutAndStderr("git", args...)
//	if err != nil {
//		return "", errs.WithEF(err, data.WithField("stdout", stdout).WithField("stderr", stderr), "Failed to get git head commit hash")
//	}
//	return stdout, nil
//}
//
//
//func (r Repository) IsCommitHashExists(commitHash string) error {
//	stdout, stderr, err := runner.ExecCmdGetStdoutAndStderr("git", "-C", r.repoDir, "cat-file", "-e", commitHash)
//	if err != nil {
//		return errs.WithEF(err, r.logData.WithField("commit", commitHash).
//			WithField("stdout", stdout).
//			WithField("stderr", stderr), "Git hash not found")
//	}
//	return nil
//}
//
//func (r Repository) GetRemoteOriginURL() (string, error) {
//	stdout, stderr, err := runner.ExecCmdGetStdoutAndStderr("git", "-C", r.repoDir, "config", "--get", "remote.origin.url")
//	if err != nil {
//		return "", errs.WithEF(err, r.logData.WithField("stderr", stderr), "Failed to get git remote url")
//	}
//	return stdout, nil
//}
//
//func (r Repository) GetCurrentBranch() (string, error) {
//	stdout, stderr, err := runner.ExecCmdGetStdoutAndStderr("git", "-C", r.repoDir, "symbolic-ref", "--quiet", "HEAD")
//	if err != nil {
//		return "", errs.WithEF(err, r.logData.WithField("stderr", stderr), "Failed to get git current branch")
//	}
//	branch := firstLine(stdout)
//	return strings.TrimPrefix(branch, "refs/heads/"), nil
//}
//
//func (r Repository) IsFileExistsInRevision(file string, revision string) error {
//	if err := r.IsCommitHashExists(revision); err != nil {
//		return errs.WithEF(err, r.logData.WithField("revision", revision), "cannot get file content for un-existing revision")
//	}
//
//	fileAbsolutePath, err := filepath.Abs(file)
//	if err != nil {
//		return errs.WithEF(err, r.logData.WithField("file", file), "Failed to get absolute path of file")
//	}
//
//	_, err = runner.ExecCmdGetOutput("git", "-C", r.repoDir, "show", revision+":"+strings.TrimPrefix(fileAbsolutePath, r.repoDir+"/"))
//	if err != nil {
//		return errs.WithEF(err, r.logData.WithField("file", file).WithField("revision", revision),
//			"Failed to get content of file for revision")
//	}
//	return nil
//}
//
//func (r Repository) GetFileContentAndDateInRevision(file string, revision string) (string, time.Time, error) {
//	t := time.Time{}
//
//	if err := r.IsCommitHashExists(revision); err != nil {
//		return "", t, errs.WithEF(err, r.logData.WithField("revision", revision), "cannot get file content for un-existing revision")
//	}
//
//	fileAbsolutePath, err := filepath.Abs(file)
//	if err != nil {
//		return "", t, errs.WithEF(err, r.logData.WithField("file", file), "Failed to get absolute path of file")
//	}
//
//	content, err := runner.ExecCmdGetOutput("git", "-C", r.repoDir, "show", revision+":"+strings.TrimPrefix(fileAbsolutePath, r.repoDir+"/"))
//	if err != nil {
//		return "", t, errs.WithEF(err, r.logData.WithField("file", file).WithField("revision", revision),
//			"Failed to get content of file for revision")
//	}
//
//	date, err := runner.ExecCmdGetOutput("git", "-C", r.repoDir,
//		"log", revision, "-1", "--format=%ct", "--", fileAbsolutePath,
//	)
//	if err != nil {
//		return "", t, errs.WithEF(err, r.logData.WithField("file", file), "Failed to get file commit date")
//	}
//
//	i, err := strconv.ParseInt(date, 10, 64)
//	if err != nil {
//		return "", t, errs.WithEF(err, r.logData.WithField("file", file), "Failed to parse file commit date from git")
//	}
//	t = time.Unix(i, 0)
//
//	return content, t, nil
//}
//
/////////////////////////
//
//// taken from github-cli to process git output
//func firstLine(output string) string {
//	if i := strings.IndexAny(output, "\n"); i >= 0 {
//		return output[0:i]
//	}
//	return output
//}
