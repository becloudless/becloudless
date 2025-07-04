package app

import (
	"context"
	"embed"
	"github.com/becloudless/becloudless/pkg/version"
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

const pathAssets = "assets"
const PathVersionAssetsPrefix = pathAssets + ".v"
const pathLock = "lock"
const pathVersion = "version"
const pathVersionLock = "version.lock"

type App struct {
	Name string
	Home string

	version version.SemVersion
	assets  embed.FS
}

func (app *App) SetVersion(v version.SemVersion) {
	app.version = v
}

func (app *App) SetAssets(assets embed.FS) {
	app.assets = assets
}

func (app *App) DefaultHomeFolder() string {
	home, err := homedir.Dir()
	if err != nil {
		logs.WithE(err).Warn("Failed to find home directory")
		home = filepath.Join(os.TempDir(), app.Name)
	}
	return filepath.Join(home, ".config/"+app.Name)
}

func (app *App) PrepareHome() error {
	if err := os.MkdirAll(app.Home, 0755); err != nil {
		return errs.WithE(err, "Failed to create "+app.Name+" home directory")
	}

	lock := fslock.New(filepath.Join(app.Home, pathLock))
	if err := lock.Lock(); err != nil {
		return errs.WithE(err, "Failed to get home preparation lock")
	}

	defer lock.Unlock()

	bytes, err := os.ReadFile(filepath.Join(app.Home, pathVersion))
	if err != nil {
		logs.WithE(err).Warn("Failed to read home version. May be first run")
	}

	if string(bytes) != app.version.String() || err != nil {
		logs.
			WithField("homeVersion", string(bytes)).
			WithField("currentVersion", app.version.String()).
			Info(app.Name + " version changed, extract of assets required")

		assetsPath := filepath.Join(app.Home, pathAssets)
		versionAssetsName := PathVersionAssetsPrefix + app.version.String()
		versionAssetsPath := filepath.Join(app.Home, versionAssetsName)

		if err := Restore(context.TODO(), versionAssetsPath); err != nil {
			return errs.WithEF(err, data.WithField("path", versionAssetsPath), "Failed to restore assets")
		}

		if err := os.RemoveAll(assetsPath); err != nil {
			return errs.WithEF(err, data.WithField("path", assetsPath), "Failed to cleanup old assets")
		}

		if err := os.Symlink(filepath.Join(".", versionAssetsName), assetsPath); err != nil {
			return errs.WithE(err, "Unable to activate new assets")
		}

		if err := os.WriteFile(filepath.Join(app.Home, pathVersion), []byte(app.version.String()), 0644); err != nil {
			logs.WithE(err).Error("Failed to write current bbc version to home")
		}
	}

	if err := app.cleanupAssets(); err != nil {
		logs.WithE(err).Warn("Failed to cleanup bbc assets")
	}

	return nil
}

///////////////////

func (app *App) cleanupAssets() error {
	dir, err := os.ReadDir(app.Home)
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
		if oldestAssets == PathVersionAssetsPrefix+app.version.String() {
			logs.WithField("assets", oldestAssets).Debug("oldest app assets version is currently used version, not cleaning it up")
			return nil
		}
		if err := os.RemoveAll(filepath.Join(app.Home, oldestAssets)); err != nil {
			return errs.WithEF(err, data.WithField("folder", filepath.Join(app.Home, oldestAssets)), "Failed to cleanup old bbc assets")
		}
	}
	return nil
}
