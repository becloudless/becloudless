package version

import (
	"fmt"
	"github.com/becloudless/becloudless/pkg/git"
	"github.com/n0rad/go-erlog/data"
	"github.com/n0rad/go-erlog/errs"
	"strconv"
	"time"
)

func GenerateVersionFromDateAndGitState(majorVersion int, gitFolder string) (string, error) {
	now := time.Now().UTC()
	dateStr := now.Format("060102") // YYMMDD
	timeStr := now.Format("1504")   // HHMM

	// Convert time to integer to remove leading zeros
	timeInt, err := strconv.Atoi(timeStr)
	if err != nil {
		return "", errs.WithE(err, "failed to parse time")
	}

	repository, err := git.OpenRepository(gitFolder)
	if err != nil {
		return "", errs.WithEF(err, data.WithField("path", gitFolder), "failed to open git repository")
	}

	hash, err := repository.HeadCommitHash(true)
	if err != nil {
		return "", errs.WithE(err, "failed to get git commit hash")
	}

	return fmt.Sprintf("%d.%s.%d-H%s", majorVersion, dateStr, timeInt, hash), nil
}
