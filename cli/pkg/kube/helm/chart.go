package helm

import (
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"

	"github.com/goccy/go-yaml"
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
	testChart    *Chart
	ciFolder     string
	utFolder     string
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
	if len(c.chart.Metadata.Dependencies) == 0 {
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

	if c.IsLibraryChart() {
		if c.testChart == nil {
			if err := c.PrepareTestChart(); err != nil {
				return errs.WithE(err, "Failed to prepare test chart")
			}
		}
		return c.testChart.runCiTest()
	}

	return c.runCiTest()
}

/////////

const ciTestFileSuffix = "-values.yaml"
const ciResultFileSuffix = "-result.yaml"

func (c *Chart) runCiTest() error {
	// read ci/ folder for file with -values.yaml
	files, err := os.ReadDir(c.ciFolder)
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
			valuesPath := filepath.Join(c.ciFolder, file.Name())

			values, err := chartutil.ReadValuesFile(valuesPath)
			if err != nil {
				return errs.WithEF(err, data.WithField("file", valuesPath), "Failed to read values file")
			}

			resultPath := filepath.Join(c.ciFolder, strings.TrimSuffix(file.Name(), ciTestFileSuffix)+ciResultFileSuffix)
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

func (c *Chart) PrepareTestChart() error {
	if !c.IsLibraryChart() {
		c.testChart = c
		return nil
	}

	tempDir, err := os.MkdirTemp("", "base-chart-*")
	if err != nil {
		return errs.WithE(err, "Failed to create temporary directory for test chart")
	}

	// prepate the test chart directories and files
	ChartMetadata := chart.Metadata{
		Name:        c.chart.Metadata.Name + "-test",
		Version:     c.chart.Metadata.Version,
		AppVersion:  c.chart.Metadata.AppVersion,
		Description: c.chart.Metadata.Description,
		Type:        "application",
		Dependencies: []*chart.Dependency{
			{
				Name:       c.chart.Metadata.Name,
				Version:    ">0.0.0-0",
				Repository: "file://" + c.path,
			},
		},
	}

	yamlData, err := yaml.Marshal(ChartMetadata)
	if err != nil {
		return errs.WithE(err, "Failed to marshal chart metadata to YAML")
	}
	if err := os.WriteFile(filepath.Join(tempDir, "Chart.yaml"), yamlData, 0644); err != nil {
		return errs.WithE(err, "Failed to write Chart.yaml file")
	}

	if err := os.MkdirAll(filepath.Join(tempDir, "templates"), 0755); err != nil {
		return errs.WithE(err, "Failed to create templates directory")
	}

	var baseTemplate = "{{- include \"" + c.chart.Metadata.Name + ".loader.all\" . }}\n"
	if err := os.WriteFile(filepath.Join(tempDir, "templates", "loader.yaml"), []byte(baseTemplate), 0644); err != nil {
		return errs.WithE(err, "Failed to write loader.yaml file")
	}

	chart, err := loader.LoadDir(tempDir)
	if err != nil {
		return errs.WithE(err, "Failed to load chart")
	}

	c.testChart = &Chart{
		path:         tempDir,
		chart:        chart,
		ciFolder:     filepath.Join(c.path, "ci"),
		utFolder:     filepath.Join(c.path, "tests"),
		actionConfig: c.actionConfig,
		settings:     c.settings,
	}

	if err := c.testChart.UpdateDependencies(); err != nil {
		return errs.WithE(err, "Failed to update dependencies")
	}

	// Reload the chart now that dependencies have been downloaded into the
	// charts/ directory, otherwise the in-memory chart (loaded above, before
	// dependencies existed on disk) won't include the dependency's templates
	// (e.g. named templates like "base.loader.all"), causing rendering to
	// fail or produce no output.
	reloadedChart, err := loader.LoadDir(tempDir)
	if err != nil {
		return errs.WithE(err, "Failed to reload chart after updating dependencies")
	}
	c.testChart.chart = reloadedChart

	return nil
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
