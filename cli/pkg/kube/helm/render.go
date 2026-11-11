package helm

import (
	"log/slog"
	"os"
	"path/filepath"
	"regexp"
	"strings"

	"github.com/n0rad/go-erlog/data"
	"github.com/n0rad/go-erlog/errs"
	"helm.sh/helm/v4/pkg/action"
	chartcommon "helm.sh/helm/v4/pkg/chart/common"
	"helm.sh/helm/v4/pkg/chart/loader"
	chart "helm.sh/helm/v4/pkg/chart/v2"
	"helm.sh/helm/v4/pkg/cli"
	"helm.sh/helm/v4/pkg/release"
)

const fileRepositoryPrefix = "file://"

// loadChartDir loads the chart folder. Only the charts of apiVersion v1 and v2 are supported (the ones of Helm 3 and 4).
func loadChartDir(dir string) (*chart.Chart, error) {
	loaded, err := loader.LoadDir(dir)
	if err != nil {
		return nil, err
	}
	c, ok := loaded.(*chart.Chart)
	if !ok {
		return nil, errs.WithF(data.WithField("path", dir), "Unsupported chart apiVersion, only v1 and v2 charts are supported")
	}
	return c, nil
}

// LoadChartWithLocalDependencies loads the chart folder, with its dependencies declared with a `file://` repository.
// Dependencies are loaded in memory, so nothing is written in the chart folder (no charts/ folder, no Chart.lock).
func LoadChartWithLocalDependencies(chartPath string) (*chart.Chart, error) {
	absPath, err := filepath.Abs(chartPath)
	if err != nil {
		return nil, errs.WithEF(err, data.WithField("path", chartPath), "Failed to resolve absolute path")
	}

	c, err := loadChartDir(absPath)
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
		depChart, err := loadChartDir(depPath)
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
	actionConfig.SetLogger(slog.DiscardHandler)
	if err := actionConfig.Init(settings.RESTClientGetter(), namespace, os.Getenv("HELM_DRIVER")); err != nil {
		return "", errs.WithE(err, "Failed to initialize action configuration")
	}

	parsedKubeVersion, err := chartcommon.ParseKubeVersion(kubeVersion)
	if err != nil {
		return "", errs.WithEF(err, data.WithField("kubeVersion", kubeVersion), "Failed to parse kube version")
	}

	install := action.NewInstall(actionConfig)
	install.DryRunStrategy = action.DryRunClient
	install.Replace = true
	install.ReleaseName = releaseName
	install.Namespace = namespace
	install.KubeVersion = parsedKubeVersion
	install.APIVersions = []string{}
	install.IncludeCRDs = true

	rel, err := install.Run(c, values)
	if err != nil {
		return "", errs.WithEF(err, data.WithField("chart", c.Name()).WithField("release", releaseName), "Failed to render chart")
	}
	return manifestOf(rel)
}

// manifestOf returns the rendered manifest of a release.
// Helm 4 keeps the trailing blank lines of every rendered document, which Helm 3 trimmed. They are removed to keep
// the same output as Helm 3.
func manifestOf(rel release.Releaser) (string, error) {
	accessor, err := release.NewAccessor(rel)
	if err != nil {
		return "", errs.WithE(err, "Failed to read the release")
	}
	manifest := documentSeparatorRegexp.ReplaceAllString(accessor.Manifest(), "\n---\n# Source: ")
	if manifest = strings.TrimRight(manifest, "\n"); manifest == "" {
		return "", nil
	}
	return manifest + "\n", nil
}

var documentSeparatorRegexp = regexp.MustCompile(`\n{2,}---\n# Source: `)
