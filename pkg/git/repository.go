package git

import (
	"github.com/becloudless/becloudless/pkg/utils"
	"github.com/n0rad/go-erlog/data"
	"github.com/n0rad/go-erlog/errs"
	"github.com/n0rad/go-erlog/logs"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"time"
)

type Repository struct {
	repoDir string
	logData data.Fields
}

// OpenRepository
// path support any dir/file path in the repository to init
func OpenRepository(path string) (*Repository, error) {
	stat, err := os.Stat(path)
	if err != nil {
		return nil, errs.WithEF(err, data.WithField("path", path), "Failed to read git repository")
	}
	if !stat.IsDir() {
		path = filepath.Dir(path)
	}

	path, stderr, err := utils.ExecCmdGetStdoutAndStderr("git", "-C", path, "rev-parse", "--show-toplevel")
	if err != nil {
		return nil, errs.WithEF(err, data.WithField("stderr", stderr).WithField("path", path), "Failed to get git root folder")
	}

	return &Repository{
		repoDir: path,
		logData: data.WithField("repo", path),
	}, nil
}

func CloneRepository(path string, url string) (*Repository, error) {
	if err := os.MkdirAll(path, 0755); err != nil {
		return nil, errs.WithEF(err, data.WithField("path", path), "Failed to create folder to clone git repository")
	}
	logs.WithField("url", url).Info("Cloning repository...")
	if err := utils.ExecCmd("git", "clone", url, path); err != nil {
		return nil, errs.WithEF(err, data.WithField("path", path).WithField("repo", url), "Failed to clone git repository")
	}
	return &Repository{
		repoDir: path,
		logData: data.WithField("repo", path),
	}, nil
}

/////////////////////////

func (g Repository) Root() string {
	return g.repoDir
}

func (g Repository) HeadCommitHash(short bool) (string, error) {
	args := []string{"-C", g.repoDir, "rev-parse", "HEAD"}
	if short {
		args = append(args, "--short")
	}
	stdout, stderr, err := utils.ExecCmdGetStdoutAndStderr("git", args...)
	if err != nil {
		return "", errs.WithEF(err, data.WithField("stdout", stdout).WithField("stderr", stderr), "Failed to get git head commit hash")
	}
	return stdout, nil
}

func (g Repository) Checkout(ref string) error {
	if err := utils.ExecCmd("git", "-C", g.repoDir, "checkout", "-q", ref); err != nil {
		return errs.WithEF(err, g.logData.WithField("path", g.repoDir).WithField("ref", ref), "Failed to checkout ref")
	}
	return nil
}

func (g Repository) IsCommitHashExists(commitHash string) error {
	stdout, stderr, err := utils.ExecCmdGetStdoutAndStderr("git", "-C", g.repoDir, "cat-file", "-e", commitHash)
	if err != nil {
		return errs.WithEF(err, g.logData.WithField("commit", commitHash).
			WithField("stdout", stdout).
			WithField("stderr", stderr), "Git hash not found")
	}
	return nil
}

func (g Repository) GetRemoteOriginURL() (string, error) {
	stdout, stderr, err := utils.ExecCmdGetStdoutAndStderr("git", "-C", g.repoDir, "config", "--get", "remote.origin.url")
	if err != nil {
		return "", errs.WithEF(err, g.logData.WithField("stderr", stderr), "Failed to get git remote url")
	}
	return stdout, nil
}

func (g Repository) GetCurrentBranch() (string, error) {
	stdout, stderr, err := utils.ExecCmdGetStdoutAndStderr("git", "-C", g.repoDir, "symbolic-ref", "--quiet", "HEAD")
	if err != nil {
		return "", errs.WithEF(err, g.logData.WithField("stderr", stderr), "Failed to get git current branch")
	}
	branch := firstLine(stdout)
	return strings.TrimPrefix(branch, "refs/heads/"), nil
}

func (g Repository) IsFileExistsInRevision(file string, revision string) error {
	if err := g.IsCommitHashExists(revision); err != nil {
		return errs.WithEF(err, g.logData.WithField("revision", revision), "cannot get file content for un-existing revision")
	}

	fileAbsolutePath, err := filepath.Abs(file)
	if err != nil {
		return errs.WithEF(err, g.logData.WithField("file", file), "Failed to get absolute path of file")
	}

	_, err = utils.ExecCmdGetOutput("git", "-C", g.repoDir, "show", revision+":"+strings.TrimPrefix(fileAbsolutePath, g.repoDir+"/"))
	if err != nil {
		return errs.WithEF(err, g.logData.WithField("file", file).WithField("revision", revision),
			"Failed to get content of file for revision")
	}
	return nil
}

func (g Repository) GetFileContentAndDateInRevision(file string, revision string) (string, time.Time, error) {
	t := time.Time{}

	if err := g.IsCommitHashExists(revision); err != nil {
		return "", t, errs.WithEF(err, g.logData.WithField("revision", revision), "cannot get file content for un-existing revision")
	}

	fileAbsolutePath, err := filepath.Abs(file)
	if err != nil {
		return "", t, errs.WithEF(err, g.logData.WithField("file", file), "Failed to get absolute path of file")
	}

	content, err := utils.ExecCmdGetOutput("git", "-C", g.repoDir, "show", revision+":"+strings.TrimPrefix(fileAbsolutePath, g.repoDir+"/"))
	if err != nil {
		return "", t, errs.WithEF(err, g.logData.WithField("file", file).WithField("revision", revision),
			"Failed to get content of file for revision")
	}

	date, err := utils.ExecCmdGetOutput("git", "-C", g.repoDir,
		"log", revision, "-1", "--format=%ct", "--", fileAbsolutePath,
	)
	if err != nil {
		return "", t, errs.WithEF(err, g.logData.WithField("file", file), "Failed to get file commit date")
	}

	i, err := strconv.ParseInt(date, 10, 64)
	if err != nil {
		return "", t, errs.WithEF(err, g.logData.WithField("file", file), "Failed to parse file commit date from git")
	}
	t = time.Unix(i, 0)

	return content, t, nil
}

///////////////////////

// taken from github-cli to process git output
func firstLine(output string) string {
	if i := strings.IndexAny(output, "\n"); i >= 0 {
		return output[0:i]
	}
	return output
}
