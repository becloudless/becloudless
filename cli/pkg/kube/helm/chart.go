package helm

import (
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"

	"github.com/n0rad/go-erlog/data"
	"github.com/n0rad/go-erlog/errs"
	"github.com/n0rad/go-erlog/logs"
	"helm.sh/helm/v3/pkg/action"
	"helm.sh/helm/v3/pkg/chart"
	"helm.sh/helm/v3/pkg/chart/loader"
	"helm.sh/helm/v3/pkg/chartutil"
	"helm.sh/helm/v3/pkg/cli"
	"helm.sh/helm/v3/pkg/downloader"
	"helm.sh/helm/v3/pkg/getter"
)

type Chart struct {
	path         string
	chart        *chart.Chart
	actionConfig *action.Configuration
	settings     *cli.EnvSettings
}

func OpenChart(chartPath string, settings *cli.EnvSettings) (*Chart, error) {
	chartPath, err := filepath.Abs(chartPath)
	if err != nil {
		return nil, errs.WithEF(err, data.WithField("path", chartPath), "Failed to resolve absolute path")
	}

	chartYamlPath := filepath.Join(chartPath, "Chart.yaml")
	if _, err := os.Stat(chartYamlPath); err != nil {
		if os.IsNotExist(err) {
			return nil, errs.WithF(data.WithField("path", chartPath), "No Chart.yaml found")
		}
		return nil, errs.WithEF(err, data.WithField("path", chartPath), "Failed to check for Chart.yaml")
	}

	// Create action configuration
	actionConfig := new(action.Configuration)
	if err := actionConfig.Init(settings.RESTClientGetter(), settings.Namespace(), os.Getenv("HELM_DRIVER"), func(format string, v ...interface{}) {
		_, _ = fmt.Fprintf(os.Stderr, format, v...)
	}); err != nil {
		return nil, errs.WithE(err, "Failed to initialize action configuration")
	}

	// Load the chart
	chart, err := loader.LoadDir(chartPath)
	if err != nil {
		return nil, errs.WithE(err, "Failed to load chart")
	}

	return &Chart{
		path:         chartPath,
		chart:        chart,
		actionConfig: actionConfig,
		settings:     settings,
	}, nil
}

func (c *Chart) IsLibraryChart() bool {
	return c.chart.Metadata.Type == "library"
}

func (c *Chart) UpdateDependencies() error {
	// Check if the chart has dependencies
	if c.chart.Metadata.Dependencies == nil || len(c.chart.Metadata.Dependencies) == 0 {
		logs.WithField("chart", c.chart.Metadata.Name).Debug("No dependencies found, skipping dependency update")
		return nil
	}

	// Create dependency manager
	man := &downloader.Manager{
		Out:              os.Stdout,
		ChartPath:        c.path,
		Keyring:          c.settings.RepositoryConfig,
		SkipUpdate:       false,
		Getters:          getter.All(c.settings),
		RepositoryConfig: c.settings.RepositoryConfig,
		RepositoryCache:  c.settings.RepositoryCache,
		Debug:            c.settings.Debug,
	}

	// Download dependencies
	if err := man.Update(); err != nil {
		return errs.WithE(err, "Failed to update dependencies")
	}

	return nil
}

func (c *Chart) RunCITests() error {
	logs.WithField("chart", c.chart.Metadata.Name).Info("Running chart CI tests")

	// read ci/ folder for file with -values.yaml
	ciDir := filepath.Join(c.path, "ci")
	files, err := os.ReadDir(ciDir)
	if err != nil {
		if os.IsNotExist(err) {
			logs.WithField("chart", c.chart.Metadata.Name).Info("No ci/ directory found, skipping CI tests")
			return nil
		}
		return errs.WithE(err, "Failed to read ci/ directory")
	}

	for _, file := range files {
		if file.IsDir() {
			continue
		}
		if strings.HasSuffix(file.Name(), ciTestFileSuffix) {
			logs.WithField("file", file.Name()).Info("Running test")
			valuesPath := filepath.Join(ciDir, file.Name())

			values, err := chartutil.ReadValuesFile(valuesPath)
			if err != nil {
				return errs.WithEF(err, data.WithField("file", valuesPath), "Failed to read values file")
			}

			resultPath := filepath.Join(ciDir, strings.TrimSuffix(file.Name(), ciTestFileSuffix)+ciResultFileSuffix)
			resultFile, err := os.Create(resultPath)
			if err != nil {
				return errs.WithEF(err, data.WithField("file", resultPath), "Failed to create result file")
			}
			defer resultFile.Close()

			if err := c.render(values.AsMap(), "1.31.0", resultFile); err != nil {
				return errs.WithEF(err, data.WithField("file", valuesPath), "Failed to render chart with CI values")
			}
		}
	}

	return nil
}

/////////

const ciTestFileSuffix = "-values.yaml"
const ciResultFileSuffix = "-result.yaml"

func (c *Chart) PrepareDownstreamChart(outputDir string) (*Chart, error) {
	// create temporary directory for the downstream chart
	tempDir, err := os.MkdirTemp("", "downstream-chart-*")
	if err != nil {
		return nil, errs.WithE(err, "Failed to create temporary directory for downstream chart")
	}

	// prepate the downstream chart directories and files

}

func (c *Chart) render(values map[string]interface{}, kubeVersion string, output io.Writer) error {
	// Create install action (used for templating)
	install := action.NewInstall(c.actionConfig)
	install.DryRun = true
	install.ReleaseName = "test-release"
	install.Replace = true
	install.ClientOnly = true
	install.APIVersions = []string{}
	install.IncludeCRDs = true

	// Set the Kubernetes version used for Capabilities.KubeVersion, since
	// ClientOnly mode otherwise falls back to Helm's default (v1.20.0),
	// which can be incompatible with a chart's kubeVersion constraint.
	parsedKubeVersion, err := chartutil.ParseKubeVersion(kubeVersion)
	if err != nil {
		return errs.WithEF(err, data.WithField("kubeVersion", kubeVersion), "Failed to parse kube version")
	}
	install.KubeVersion = parsedKubeVersion

	release, err := install.Run(c.chart, values)
	if err != nil {
		return errs.WithE(err, "Failed to run the templating")
	}

	if _, err := output.Write([]byte(release.Manifest)); err != nil {
		return errs.WithE(err, "Failed to write manifest to output")
	}

	return nil
}
