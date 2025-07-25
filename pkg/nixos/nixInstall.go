package nixos

import (
	"archive/tar"
	"github.com/becloudless/becloudless/pkg/system/runner"
	"github.com/n0rad/go-erlog/data"
	"github.com/n0rad/go-erlog/errs"
	"github.com/n0rad/go-erlog/logs"
	"github.com/xi2/xz"
	"io"
	"net/http"
	"os"
	"os/exec"
	"path"
	"runtime"
)

// TODO renovate
const NIX_VERSION = "2.30.0"

func EnsureNixIsAvailable() error {
	_, err := exec.LookPath("nix")
	if err != nil {
		return errs.WithE(err, "nix command is not available")
	}
	return nil
}

func InstallNixLocally(password []byte) error {
	arch := runtime.GOARCH
	switch arch {
	case "amd64":
		arch = "x86_64"
	case "arm64":
		arch = "aarch64"
	}
	NixFoldername := "nix-" + NIX_VERSION + "-" + arch + "-" + runtime.GOOS
	NixFilename := NixFoldername + ".tar.xz"
	NixReleaseUrl := "https://releases.nixos.org/nix/nix-" + NIX_VERSION + "/" + NixFilename

	temp, err := os.MkdirTemp(os.TempDir(), "bcl")
	if err != nil {
		return errs.With("Failed to create temporary directory to download nix")
	}
	defer func(temp string) {
		//_ = os.RemoveAll(temp)
	}(temp)

	filePath := path.Join(temp, NixFilename)
	out, err := os.Create(filePath)
	defer out.Close()

	logs.WithField("url", NixReleaseUrl).Info("Downloading nix package")
	resp, err := http.Get(NixReleaseUrl)
	defer resp.Body.Close()
	if err != nil {
		return errs.WithEF(err, data.WithField("url", NixReleaseUrl), "Failed to download nix package")
	}

	if _, err := io.Copy(out, resp.Body); err != nil {
		return errs.WithE(err, "Failed to download nix package")
	}

	logs.WithField("path", filePath).Info("Extracting nix package")
	if err := untarXZ(temp, out); err != nil {
		return errs.WithEF(err, data.WithField("file", filePath), "Failed to untar file")
	}

	localRun := runner.NewLocalRunner()
	run, err := runner.NewInlineSudoRunner(localRun, password)
	if err != nil {
		return errs.WithE(err, "Failed to prepare sudo runner")
	}
	installPath := path.Join(temp, NixFoldername, "install")
	logs.WithField("path", NixReleaseUrl).Info("Running nix install")
	if err := run.ExecCmd("/bin/sh", installPath, "--yes"); err != nil {
		return errs.WithE(err, "Nix install failed")
	}
	return nil
}

func untarXZ(target string, file *os.File) error {
	if _, err := file.Seek(0, io.SeekStart); err != nil {
		return errs.WithE(err, "Failed to read from beginning of file")
	}
	r, err := xz.NewReader(file, 0)
	if err != nil {
		return errs.WithE(err, "Failed to create xz reader")
	}
	tr := tar.NewReader(r)
	for {
		hdr, err := tr.Next()
		if err == io.EOF {
			break
		}
		if err != nil {
			return errs.WithE(err, "Failed reading files in archive")
		}
		switch hdr.Typeflag {
		case tar.TypeDir:
			folderPath := path.Join(target, hdr.Name)
			if err := os.MkdirAll(folderPath, 0777); err != nil {
				return errs.WithEF(err, data.WithField("path", folderPath), "Failed to create directory")
			}
		case tar.TypeReg, tar.TypeRegA:
			dir := path.Dir(hdr.Name)
			if dir != "" {
				folderPath := path.Join(target, dir)
				if err := os.MkdirAll(folderPath, 0777); err != nil {
					return errs.WithEF(err, data.WithField("path", folderPath), "Failed to create directory")
				}
			}

			filePath := path.Join(target, hdr.Name)
			w, err := os.OpenFile(filePath, os.O_RDWR|os.O_CREATE|os.O_TRUNC, os.FileMode(hdr.Mode))
			if err != nil {
				return errs.WithEF(err, data.WithField("path", filePath), "Failed to create file")
			}
			_, err = io.Copy(w, tr)
			w.Close()
			if err != nil {
				return errs.WithEF(err, data.WithField("path", filePath), "Failed to copy content to file")
			}
		}
	}
	return nil
}
