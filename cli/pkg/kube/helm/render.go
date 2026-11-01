package helm

import (
	"os"
	"path/filepath"
	"strings"

	"github.com/n0rad/go-erlog/data"
	"github.com/n0rad/go-erlog/errs"
	"helm.sh/helm/v3/pkg/action"
	"helm.sh/helm/v3/pkg/chart"
	"helm.sh/helm/v3/pkg/chart/loader"
	"helm.sh/helm/v3/pkg/chartutil"
	"helm.sh/helm/v3/pkg/cli"
)

const fileRepositoryPrefix = "file://"

// LoadChartWithLocalDependencies loads the chart folder, with its dependencies declared with a `file://` repository.
// Dependencies are loaded in memory, so nothing is written in the chart folder (no charts/ folder, no Chart.lock).
func LoadChartWithLocalDependencies(chartPath string) (*chart.Chart, error) {
	absPath, err := filepath.Abs(chartPath)
	if err != nil {
		return nil, errs.WithEF(err, data.WithField("path", chartPath), "Failed to resolve absolute path")
	}

	c, err := loader.LoadDir(absPath)
	if err != nil {
		return nil, errs.WithEF(err, data.WithField("path", absPath), "Failed to load chart")
	}

	if err := addLocalDependencies(c, absPath); err != nil {
		return nil, err
	}
	return c, nil
}

func addLocalDependencies(c *chart.Chart, chartPath string) error {
	loaded := map[string]bool{}
	for _, d := range c.Dependencies() {
		loaded[d.Name()] = true
	}

	for _, dep := range c.Metadata.Dependencies {
		if loaded[dep.Name] {
			continue
		}
		if !strings.HasPrefix(dep.Repository, fileRepositoryPrefix) {
			return errs.WithF(data.WithField("chart", c.Name()).WithField("dependency", dep.Name).WithField("repository", dep.Repository),
				"Only dependencies with a file:// repository can be loaded locally")
		}

		depPath := filepath.Join(chartPath, strings.TrimPrefix(dep.Repository, fileRepositoryPrefix))
		depChart, err := loader.LoadDir(depPath)
		if err != nil {
			return errs.WithEF(err, data.WithField("chart", c.Name()).WithField("dependency", dep.Name).WithField("path", depPath), "Failed to load chart dependency")
		}
		if err := addLocalDependencies(depChart, depPath); err != nil {
			return err
		}
		c.AddDependency(depChart)
	}
	return nil
}

// RenderChart renders the chart like `helm template` would, without any cluster access, and returns the manifest.
func RenderChart(c *chart.Chart, values map[string]any, releaseName string, namespace string, kubeVersion string) (string, error) {
	settings := cli.New()
	actionConfig := new(action.Configuration)
	if err := actionConfig.Init(settings.RESTClientGetter(), namespace, os.Getenv("HELM_DRIVER"), func(string, ...interface{}) {}); err != nil {
		return "", errs.WithE(err, "Failed to initialize action configuration")
	}

	parsedKubeVersion, err := chartutil.ParseKubeVersion(kubeVersion)
	if err != nil {
		return "", errs.WithEF(err, data.WithField("kubeVersion", kubeVersion), "Failed to parse kube version")
	}

	install := action.NewInstall(actionConfig)
	install.DryRun = true
	install.ClientOnly = true
	install.Replace = true
	install.ReleaseName = releaseName
	install.Namespace = namespace
	install.KubeVersion = parsedKubeVersion
	install.APIVersions = []string{}
	install.IncludeCRDs = true

	release, err := install.Run(c, values)
	if err != nil {
		return "", errs.WithEF(err, data.WithField("chart", c.Name()).WithField("release", releaseName), "Failed to render chart")
	}
	return release.Manifest, nil
}
