package app

import (
	"embed"
	"github.com/becloudless/becloudless/pkg/bcl/app/version"
	"github.com/juju/fslock"
	"github.com/mitchellh/go-homedir"
	"github.com/n0rad/go-erlog/data"
	"github.com/n0rad/go-erlog/errs"
	"github.com/n0rad/go-erlog/logs"
	"io"
	"io/fs"
	"os"
	"path/filepath"
	"sort"
	"strings"
)

const pathAssets = "assets"
const pathLock = "lock"
const pathVersion = "version"

type App struct {
	Name       string
	Home       string
	Version    version.SemVersion
	Assets     embed.FS
	AssetsPath string
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
		return errs.WithEF(err, data.WithField("path", app.Home), "Failed to create "+app.Name+" home directory")
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

	app.AssetsPath = filepath.Join(app.Home, pathAssets, app.Version.String())
	if app.Version.String() == "0.0.0" || string(bytes) != app.Version.String() || err != nil {
		logs.WithField("homeVersion", string(bytes)).
			WithField("currentVersion", app.Version.String()).
			Info(app.Name + " version changed")

		if err := os.RemoveAll(app.AssetsPath); err != nil {
			logs.WithE(err).Warn("Failed to cleanup current assets before extract")
		}

		if err := app.extractAssets(app.AssetsPath); err != nil {
			return errs.WithEF(err, data.WithField("path", app.AssetsPath), "Failed to restore assets")
		}

		if err := os.WriteFile(filepath.Join(app.Home, pathVersion), []byte(app.Version.String()), 0644); err != nil {
			logs.WithE(err).Error("Failed to write current " + app.Name + " version to home")
		}
	}

	if err := app.cleanupAssets(); err != nil {
		logs.WithE(err).Warn("Problem during assets cleanup")
	}

	return nil
}

///////////////////

func (app *App) extractAssets(target string) error {
	return fs.WalkDir(app.Assets, ".", func(path string, d fs.DirEntry, err error) error {
		if err != nil {
			return err
		}

		pathsWithoutPrefix := strings.Split(path, string(filepath.Separator))[1:]
		newPath := filepath.Join(append([]string{target}, pathsWithoutPrefix...)...)
		if d.IsDir() {
			return os.MkdirAll(newPath, 0755)
		}

		if !d.Type().IsRegular() {
			return errs.WithF(data.WithField("path", path), "Embedded asset is invalid, not a regular file")
		}

		r, err := app.Assets.Open(path)
		if err != nil {
			return err
		}
		defer r.Close()
		info, err := r.Stat()
		if err != nil {
			return err
		}
		w, err := os.OpenFile(newPath, os.O_CREATE|os.O_EXCL|os.O_WRONLY, 0644|info.Mode()&0755)
		if err != nil {
			return err
		}

		if _, err := io.Copy(w, r); err != nil {
			w.Close()
			return errs.WithEF(err, data.WithField("path", path), "Failed to extract asset")
		}
		return w.Close()
	})
}

func (app *App) cleanupAssets() error {
	dir, err := os.ReadDir(filepath.Join(app.Home, pathAssets))
	if err != nil {
		return errs.WithE(err, "Failed to read home folder")
	}
	var assets []string
	for _, entry := range dir {
		assets = append(assets, entry.Name())
	}

	// Multiple process could be running in parallel and there is no way to know if we can clean up assets without monitoring process.
	// To not do process monitoring, we can assume the app will not be updated more than 2 times without having process completed
	// So we keep 2 assets + one being installed
	if len(assets) > 3 {
		sort.Slice(assets, func(i, j int) bool {
			ai, err := version.Parse(assets[i])
			if err != nil {
				logs.WithEF(err, data.WithField("assets", i)).Warn("Failed to read assets version")
				return false
			}
			aj, err := version.Parse(assets[j])
			if err != nil {
				logs.WithEF(err, data.WithField("assets", j)).Warn("Failed to read assets version")
				return false
			}
			return ai.Compare(aj) < 0
		})

		oldestAssets := assets[0]
		if oldestAssets == app.Version.String() {
			logs.WithField("assets", oldestAssets).Debug("oldest app assets version is currently used version, not cleaning it up")
			return nil
		}
		toCleanupPath := filepath.Join(app.Home, pathAssets, oldestAssets)
		if err := os.RemoveAll(toCleanupPath); err != nil {
			return errs.WithEF(err, data.WithField("folder", toCleanupPath), "Failed to cleanup old assets")
		}
	}
	return nil
}
