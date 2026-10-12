package helm

import (
	"os"
	"path/filepath"

	"github.com/becloudless/becloudless/pkg/version"
	"github.com/n0rad/go-erlog/data"
	"github.com/n0rad/go-erlog/errs"
	"github.com/n0rad/go-erlog/logs"
	"helm.sh/helm/v3/pkg/action"
	"helm.sh/helm/v3/pkg/registry"
)

const baseLibraryAnnotation = "base-library"

type PushOptions struct {
	// Remote is the OCI registry location, e.g. oci://ghcr.io/owner. The chart name is appended by Helm.
	Remote string
	// Version overrides the chart version when set. Defaults to a version generated from the date and git state (1.YYMMDD.HHMM-H<hash>).
	Version string
	// AppVersion overrides the chart appVersion when set.
	AppVersion string
	// Username and Password are optional. When empty, credentials from the Helm registry config (helm registry login) are used.
	Username  string
	Password  string
	PlainHTTP bool
}

// Push packages the chart and pushes it to an OCI registry.
// A library chart annotated with base-library=true is pushed together with a
// "<name>-application" chart depending on it, which renders the library loader.
func (c *Chart) Push(opts PushOptions) error {
	if !registry.IsOCI(opts.Remote) {
		return errs.WithF(data.WithField("remote", opts.Remote), "Remote must be an OCI reference (oci://...)")
	}

	clientOpts := []registry.ClientOption{
		registry.ClientOptCredentialsFile(c.settings.RegistryConfig),
		registry.ClientOptWriter(os.Stderr),
	}
	if opts.Username != "" || opts.Password != "" {
		clientOpts = append(clientOpts, registry.ClientOptBasicAuth(opts.Username, opts.Password))
	}
	if opts.PlainHTTP {
		clientOpts = append(clientOpts, registry.ClientOptPlainHTTP())
	}
	registryClient, err := registry.NewClient(clientOpts...)
	if err != nil {
		return errs.WithE(err, "Failed to create registry client")
	}
	c.actionConfig.RegistryClient = registryClient

	if opts.Version == "" {
		opts.Version, err = version.GenerateVersionFromDateAndGitState(1, c.path)
		if err != nil {
			return errs.WithE(err, "Failed to generate chart version")
		}
		logs.WithField("version", opts.Version).Info("Generated chart version")
	}

	if err := c.packageAndPush(c.path, opts); err != nil {
		return err
	}

	if c.IsLibraryChart() && c.chart.Metadata.Annotations[baseLibraryAnnotation] == "true" {
		if err := c.pushApplicationChart(opts); err != nil {
			return errs.WithE(err, "Failed to push application chart")
		}
	}

	return nil
}

func (c *Chart) pushApplicationChart(opts PushOptions) error {
	version := c.chart.Metadata.Version
	if opts.Version != "" {
		version = opts.Version
	}

	appDir, err := os.MkdirTemp("", "chart-application-*")
	if err != nil {
		return errs.WithE(err, "Failed to create temporary directory for application chart")
	}
	defer os.RemoveAll(appDir)

	name := c.chart.Metadata.Name + "-application"

	// resolve the dependency locally so it is vendored in charts/, using the local library
	if err := c.writeLoaderChart(appDir, name, version, version, "file://"+c.path); err != nil {
		return err
	}
	appChart, err := OpenChart(appDir, c.settings)
	if err != nil {
		return errs.WithE(err, "Failed to open application chart")
	}
	if err := appChart.UpdateDependencies(); err != nil {
		return errs.WithE(err, "Failed to update application chart dependencies")
	}

	// published chart must reference the library from the registry, not from a local path
	if err := c.writeLoaderChart(appDir, name, version, version, opts.Remote); err != nil {
		return err
	}
	if err := os.Remove(filepath.Join(appDir, "Chart.lock")); err != nil && !os.IsNotExist(err) {
		return errs.WithE(err, "Failed to remove Chart.lock")
	}

	appOpts := opts
	appOpts.Version = ""
	appOpts.AppVersion = ""
	return c.packageAndPush(appDir, appOpts)
}

func (c *Chart) packageAndPush(chartPath string, opts PushOptions) error {
	tmpDir, err := os.MkdirTemp("", "chart-package-*")
	if err != nil {
		return errs.WithE(err, "Failed to create temporary directory for chart package")
	}
	defer os.RemoveAll(tmpDir)

	pkg := action.NewPackage()
	pkg.Destination = tmpDir
	pkg.Version = opts.Version
	pkg.AppVersion = opts.AppVersion
	archive, err := pkg.Run(chartPath, nil)
	if err != nil {
		return errs.WithEF(err, data.WithField("path", chartPath), "Failed to package chart")
	}

	logs.WithField("archive", filepath.Base(archive)).WithField("remote", opts.Remote).Info("Pushing chart")

	push := action.NewPushWithOpts(
		action.WithPushConfig(c.actionConfig),
		action.WithPlainHTTP(opts.PlainHTTP),
		action.WithPushOptWriter(os.Stderr),
	)
	push.Settings = c.settings
	out, err := push.Run(archive, opts.Remote)
	if out != "" {
		_, _ = os.Stderr.WriteString(out)
	}
	if err != nil {
		return errs.WithEF(err, data.WithField("remote", opts.Remote), "Failed to push chart")
	}

	return nil
}
