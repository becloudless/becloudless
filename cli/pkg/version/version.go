package version

import (
	"fmt"
	"strconv"
	"time"

	"github.com/becloudless/becloudless/pkg/git"
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
