package main

import (
	"context"
	"github.com/becloudless/becloudless/version"
	"github.com/blang/semver/v4"
	"github.com/juju/fslock"
	"github.com/mitchellh/go-homedir"
	"github.com/n0rad/go-erlog/data"
	"github.com/n0rad/go-erlog/errs"
	"github.com/n0rad/go-erlog/logs"
	"os"
	"path/filepath"
	"sort"
	"strings"
)

var bcl Bcl

const pathAssets = "assets"
const PathVersionAssetsPrefix = pathAssets + ".v"
const pathLock = "lock"
const pathVersion = "version"
const pathVersionLock = "version.lock"

type Bcl struct {
	home    string
	version version.SemVersion
}

func (bcl *Bcl) SetVersion(v string) error {
	semVersion, err := semver.Parse(v)
	if err != nil {
		return errs.WithEF(err, data.WithField("Version", v), "Failed to parse Version")
	}
	bcl.version = version.SemVersion{semVersion}
	return nil
}

func (bcl *Bcl) SetHomeFolder(homeFolder string) {
	bcl.home = homeFolder
}

// PrepareAssets updates the assets in the home folder with this versions' assets, unless they're up to date.
// In order to avoid gone files, new assets are first extracted into a version-specific folder, which is then symlinked
// to the actual assets path (typically "assets"). The version-specific folder looks like "assets.v1.0.0".

func (bcl *Bcl) PrepareAssets() error {
	if err := os.MkdirAll(bcl.home, 0755); err != nil {
		return errs.WithE(err, "Failed to create the BBC home directory")
	}

	lock := fslock.New(filepath.Join(bcl.home, pathLock))
	if err := lock.Lock(); err != nil {
		return errs.WithE(err, "Failed to get asset extract lock")
	}

	defer lock.Unlock()

	bytes, err := os.ReadFile(filepath.Join(bcl.home, pathVersion))
	if err != nil {
		logs.WithE(err).Warn("Failed to read home version. May be first run")
	}

	if string(bytes) != bcl.version.String() || err != nil {
		logs.
			WithField("homeVersion", string(bytes)).
			WithField("currentVersion", bcl.version.String()).
			Info("BCL version changed, extract of assets required")

		assetsPath := filepath.Join(bcl.home, pathAssets)
		versionAssetsName := PathVersionAssetsPrefix + bcl.version.String()
		versionAssetsPath := filepath.Join(bcl.home, versionAssetsName)

		if err := Restore(context.TODO(), versionAssetsPath); err != nil {
			return errs.WithEF(err, data.WithField("path", versionAssetsPath), "Failed to restore assets")
		}

		if err := os.RemoveAll(assetsPath); err != nil {
			return errs.WithEF(err, data.WithField("path", assetsPath), "Failed to cleanup old assets")
		}

		if err := os.Symlink(filepath.Join(".", versionAssetsName), assetsPath); err != nil {
			return errs.WithE(err, "Unable to activate new assets")
		}

		if err := os.WriteFile(filepath.Join(bcl.home, pathVersion), []byte(bcl.version.String()), 0644); err != nil {
			logs.WithE(err).Error("Failed to write current bbc version to home")
		}
	}

	if err := bcl.cleanupAssets(); err != nil {
		logs.WithE(err).Warn("Failed to cleanup bbc assets")
	}

	return nil
}

func (bcl *Bcl) cleanupAssets() error {
	dir, err := os.ReadDir(bcl.home)
	if err != nil {
		return errs.WithE(err, "Failed to read bbc home folder")
	}
	var assets []string
	for _, entry := range dir {
		if strings.HasPrefix(entry.Name(), PathVersionAssetsPrefix) && entry.Name() != PathVersionAssetsPrefix+"0.0.0" {
			assets = append(assets, entry.Name())
		}
	}

	// Multiple bbc process could be running in parallel and there is no way to know if we can clean up assets without monitoring process.
	// To not do process monitoring, we can assume that bbc will not be updated more than 2 times without having process completed
	// So we keep 2 assets + one being installed
	if len(assets) > 3 {
		sort.Slice(assets, func(i, j int) bool {
			ai, err := version.Parse(strings.TrimPrefix(assets[i], PathVersionAssetsPrefix))
			if err != nil {
				logs.WithEF(err, data.WithField("assets", i)).Warn("Failed to read assets version")
				return false
			}
			aj, err := version.Parse(strings.TrimPrefix(assets[j], PathVersionAssetsPrefix))
			if err != nil {
				logs.WithEF(err, data.WithField("assets", j)).Warn("Failed to read assets version")
				return false
			}

			return ai.Compare(aj) < 0
		})

		oldestAssets := assets[0]
		if oldestAssets == PathVersionAssetsPrefix+bcl.version.String() {
			logs.WithField("assets", oldestAssets).Debug("oldest bcl assets version is currently used version, not cleaning it up")
			return nil
		}
		if err := os.RemoveAll(filepath.Join(bcl.home, oldestAssets)); err != nil {
			return errs.WithEF(err, data.WithField("folder", filepath.Join(bcl.home, oldestAssets)), "Failed to cleanup old bbc assets")
		}
	}
	return nil
}

///////////////////////////////

func DefaultHomeFolder() string {
	home, err := homedir.Dir()
	if err != nil {
		logs.WithE(err).Warn("Failed to find home directory")
		home = filepath.Join(os.TempDir(), "bcl")
	}

	return filepath.Join(home, ".config/bcl")
}
