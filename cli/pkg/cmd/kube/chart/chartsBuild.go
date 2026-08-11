package chart

import (
	"fmt"
	"os"
	"path/filepath"

	"github.com/n0rad/go-erlog/data"
	"github.com/n0rad/go-erlog/errs"
	"github.com/n0rad/go-erlog/logs"
	"github.com/spf13/cobra"
	"helm.sh/helm/v3/pkg/action"
	"helm.sh/helm/v3/pkg/chart/loader"
	"helm.sh/helm/v3/pkg/chartutil"
	"helm.sh/helm/v3/pkg/cli"
	"helm.sh/helm/v3/pkg/downloader"
	"helm.sh/helm/v3/pkg/getter"
)

func buildCmd() *cobra.Command {
	var path string
	var kubeVersion string

	cmd := &cobra.Command{
		Use:   "build",
		Args:  cobra.ExactArgs(0),
		Short: "Build a helm chart",
		RunE: func(cmd *cobra.Command, args []string) error {
			chartPath, err := filepath.Abs(path)
			if err != nil {
				return errs.WithEF(err, data.WithField("path", path), "Failed to resolve absolute path")
			}

			// Ensure a Chart.yaml exists in the chart directory
			chartYamlPath := filepath.Join(chartPath, "Chart.yaml")
			if _, err := os.Stat(chartYamlPath); err != nil {
				if os.IsNotExist(err) {
					return errs.WithF(data.WithField("path", chartPath), "no Chart.yaml found")
				}
				return errs.WithEF(err, data.WithField("path", chartPath), "Failed to check for Chart.yaml")
			}

			// Initialize Helm settings
			settings := cli.New()

			// Step 1: Helm dependency update
			fmt.Println("Running helm dependency update...")
			if err := updateDependencies(chartPath, settings); err != nil {
				return errs.WithE(err, "Failed to update dependencies")
			}

			// Step 2: Helm template
			fmt.Println("Running helm template...")
			if err := templateChart(chartPath, settings, kubeVersion); err != nil {
				return errs.WithE(err, "Failed to template chart")
			}

			logs.WithField("path", chartPath).Info("Chart build completed successfully")
			return nil
		},
	}

	cmd.Flags().StringVar(&path, "path", ".", "Chart directory path")
	cmd.Flags().StringVar(&kubeVersion, "kube-version", "1.31.0", "Kubernetes version used for Capabilities.KubeVersion")

	return cmd
}

// updateDependencies runs helm dependency update on the chart
func updateDependencies(chartPath string, settings *cli.EnvSettings) error {
	// Load the chart to check if it exists and has dependencies
	chart, err := loader.LoadDir(chartPath)
	if err != nil {
		return errs.WithEF(err, data.WithField("path", chartPath), "Failed to load chart")
	}

	// Check if the chart has dependencies
	if chart.Metadata.Dependencies == nil || len(chart.Metadata.Dependencies) == 0 {
		fmt.Println("No dependencies found, skipping dependency update")
		return nil
	}

	// Create dependency manager
	man := &downloader.Manager{
		Out:              os.Stdout,
		ChartPath:        chartPath,
		Keyring:          settings.RepositoryConfig,
		SkipUpdate:       false,
		Getters:          getter.All(settings),
		RepositoryConfig: settings.RepositoryConfig,
		RepositoryCache:  settings.RepositoryCache,
		Debug:            settings.Debug,
	}

	// Download dependencies
	if err := man.Update(); err != nil {
		return errs.WithE(err, "Failed to update dependencies")
	}

	return nil
}

// templateChart runs helm template on the chart with default values
func templateChart(chartPath string, settings *cli.EnvSettings, kubeVersion string) error {
	// Create action configuration
	actionConfig := new(action.Configuration)
	if err := actionConfig.Init(settings.RESTClientGetter(), settings.Namespace(), os.Getenv("HELM_DRIVER"), func(format string, v ...interface{}) {
		_, _ = fmt.Fprintf(os.Stderr, format, v...)
	}); err != nil {
		return errs.WithE(err, "Failed to initialize action configuration")
	}

	// Create install action (used for templating)
	install := action.NewInstall(actionConfig)
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

	// Load the chart
	chart, err := loader.LoadDir(chartPath)
	if err != nil {
		return errs.WithE(err, "Failed to load chart")
	}

	// Run the template generation
	release, err := install.Run(chart, nil) // nil for default values
	if err != nil {
		return errs.WithE(err, "Failed to run the templating")
	}

	// Print the rendered templates
	fmt.Printf("---\n# Generated templates for chart: %s\n", chart.Metadata.Name)
	fmt.Print(release.Manifest)

	return nil
}
