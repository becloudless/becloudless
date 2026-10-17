package version

import (
	"fmt"
	"strconv"
	"strings"
	"time"

	"github.com/becloudless/becloudless/pkg/git"
	"github.com/go-git/go-git/v6/plumbing"
	"github.com/n0rad/go-erlog/data"
	"github.com/n0rad/go-erlog/errs"
	"github.com/n0rad/go-erlog/logs"
)

func GenerateVersionFromDateAndGitState(majorVersion int, gitFolder string) (string, error) {
	repository, err := git.OpenRepository(gitFolder)
	if err != nil {
		return "", errs.WithEF(err, data.WithField("path", gitFolder), "failed to open git repository")
	}

	hash, err := repository.HeadCommitHash(true)
	if err != nil {
		return "", errs.WithE(err, "failed to get git commit hash")
	}

	suffix := GenerateVersionWithSuffix(majorVersion, "H"+hash)
	return suffix, nil
}

// GenerateIncrementalVersion generates a version like <major>.<YYMMDD>.<N> where N is the bugfix number,
// starting at 0 and incremented for each existing git tag "v<major>.<YYMMDD>.*" found in the repository.
func GenerateIncrementalVersion(majorVersion int, gitFolder string) (string, error) {
	repository, err := git.OpenRepository(gitFolder)
	if err != nil {
		return "", errs.WithEF(err, data.WithField("path", gitFolder), "failed to open git repository")
	}

	tags, err := repository.Repo.Tags()
	if err != nil {
		return "", errs.WithE(err, "failed to list git tags")
	}

	dateStr := time.Now().UTC().Format("060102")
	prefix := fmt.Sprintf("v%d.%s.", majorVersion, dateStr)
	next := 0
	if err := tags.ForEach(func(ref *plumbing.Reference) error {
		bugfix, ok := strings.CutPrefix(ref.Name().Short(), prefix)
		if !ok {
			return nil
		}
		n, err := strconv.Atoi(bugfix)
		if err != nil {
			return nil
		}
		if n >= next {
			next = n + 1
		}
		return nil
	}); err != nil {
		return "", errs.WithE(err, "failed to iterate git tags")
	}

	return fmt.Sprintf("%d.%s.%d", majorVersion, dateStr, next), nil
}

func GenerateVersion(majorVersion int) string {
	return GenerateVersionWithSuffix(majorVersion, "")
}

func GenerateVersionWithSuffix(majorVersion int, suffix string) string {
	now := time.Now().UTC()
	dateStr := now.Format("060102") // YYMMDD
	timeStr := now.Format("1504")   // HHMM

	// Convert time to integer to remove leading zeros
	timeInt, err := strconv.Atoi(timeStr)
	if err != nil {
		logs.WithE(err).Fatal("Failed to parse time")
	}

	version := fmt.Sprintf("%d.%s.%d", majorVersion, dateStr, timeInt)
	if suffix == "" {
		return version
	}
	return fmt.Sprintf("%s-%s", version, suffix)
}
