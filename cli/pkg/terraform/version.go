package terraform

import (
	"context"
	"os"
	"path/filepath"

	"github.com/becloudless/becloudless/pkg/utils"
	"github.com/hashicorp/go-version"
	install "github.com/hashicorp/hc-install"
	"github.com/hashicorp/hc-install/product"
	"github.com/hashicorp/hc-install/releases"
	"github.com/hashicorp/hc-install/src"
	"github.com/n0rad/go-erlog/data"
	"github.com/n0rad/go-erlog/errs"
	"github.com/n0rad/go-erlog/logs"
)

func (c *Client) ensureVersion(v *version.Version) (string, error) {
	if c.localBinaryPath != "" {
		return c.localBinaryPath, nil
	}

	binDir := filepath.Join(c.binDir, v.String())

	// Use the binary if it's already present
	dest := filepath.Join(binDir, "terraform")
	if utils.FileExists(dest) {
		c.localBinaryPath = dest
		return dest, nil
	}
	logs.WithField("version", v.String()).
		WithField("path", binDir).
		Debug("Could not find terraform version in path, downloading")

	// Otherwise, install it
	installer := install.NewInstaller()
	if err := os.MkdirAll(binDir, 0755); err != nil {
		return "", errs.WithEF(err, data.WithField("target", binDir), "failed to create binary target directory")
	}
	logs.WithField("version", v.String()).WithField("target", binDir).Info("Downloading terraform")
	dest, err := installer.Install(context.Background(), []src.Installable{
		&releases.ExactVersion{
			Product:    product.Terraform,
			Version:    v,
			InstallDir: binDir,
		},
	})
	if err != nil {
		return "", errs.WithEF(err, data.WithField("version", v.String()), "failed to download terraform version")
	}
	logs.WithField("version", v.String()).WithField("target", binDir).Info("Terraform successfully installed")

	c.localBinaryPath = dest
	return dest, nil
}
