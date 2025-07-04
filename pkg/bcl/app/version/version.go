package version

import (
	"fmt"
	"github.com/becloudless/becloudless/pkg/git"
	"github.com/blang/semver/v4"
	"github.com/n0rad/go-erlog/errs"
	"reflect"
	"strconv"
	"strings"
	"time"
)

type Version struct {
	Version    string
	Generation int64
}

type SemVersion struct {
	semver.Version
}

func Parse(v string) (SemVersion, error) {
	parse, err := semver.Parse(v)
	return SemVersion{Version: parse}, err
}

func (v SemVersion) Compare(o SemVersion) int {
	if v.Minor == o.Minor &&
		v.Major == o.Major &&
		v.Patch == o.Patch &&
		reflect.DeepEqual(v.Build, o.Build) &&
		reflect.DeepEqual(v.Pre, o.Pre) {
		return 0
	}
	return v.Version.Compare(o.Version)
}

func (v SemVersion) ToChangelogVersion() string {
	date := strconv.FormatUint(v.Minor, 10)
	dateString := date[0:4] + "-" + date[4:6] + "-" + date[6:8]
	return dateString
}

func ReverseVersions(a *[]Version) {
	for i, j := 0, len(*a)-1; i < j; i, j = i+1, j-1 {
		(*a)[i], (*a)[j] = (*a)[j], (*a)[i]
	}
}

func GenerateDateCommitVersion(repoPath string, major int) (string, error) {
	repository, err := git.OpenRepository(repoPath)
	if err != nil {
		return "", errs.WithE(err, "Failed to open repository to get commit hash")
	}

	hash, err := repository.HeadCommitHash(true)
	if err != nil {
		return "", errs.WithE(err, "Failed to generate version")
	}
	return generateDateCommitVersion(major, hash, time.Now()), nil
}

func generateDateCommitVersion(major int, hash string, now time.Time) string {
	vDay := now.Format("060102")
	vTime := strings.TrimLeft(now.Format("1504"), "0")
	if vTime == "" {
		vTime = "0"
	}
	return fmt.Sprintf("%d.%s.%s-H%s", major, vDay, vTime, hash)
}
