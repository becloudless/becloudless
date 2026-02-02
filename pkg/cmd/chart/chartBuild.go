package chart

import (
	"fmt"
	"os"

	"github.com/spf13/cobra"
	"helm.sh/helm/v3/pkg/action"
	"helm.sh/helm/v3/pkg/chart/loader"
	"helm.sh/helm/v3/pkg/cli"
	"helm.sh/helm/v3/pkg/downloader"
	"helm.sh/helm/v3/pkg/getter"
)

func buildCmd() *cobra.Command {
	cmd := &cobra.Command{
		Use:   "build",
		Args:  cobra.ExactArgs(0),
		Short: "Build a helm chart",
		RunE: func(cmd *cobra.Command, args []string) error {
			// Get current working directory
			chartPath, err := os.Getwd()
			if err != nil {
				return fmt.Errorf("failed to get current directory: %w", err)
			}

			// Initialize Helm settings
			settings := cli.New()

			// Step 1: Helm dependency update
			fmt.Println("Running helm dependency update...")
			if err := updateDependencies(chartPath, settings); err != nil {
				return fmt.Errorf("failed to update dependencies: %w", err)
			}

			// Step 2: Helm template
			fmt.Println("Running helm template...")
			if err := templateChart(chartPath, settings); err != nil {
				return fmt.Errorf("failed to template chart: %w", err)
			}

			fmt.Println("Chart build completed successfully!")
			return nil
		},
	}

	return cmd
}

// updateDependencies runs helm dependency update on the chart
func updateDependencies(chartPath string, settings *cli.EnvSettings) error {
	// Load the chart to check if it exists and has dependencies
	chart, err := loader.LoadDir(chartPath)
	if err != nil {
		return fmt.Errorf("failed to load chart from %s: %w", chartPath, err)
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
		return fmt.Errorf("failed to update dependencies: %w", err)
	}

	return nil
}

// templateChart runs helm template on the chart with default values
func templateChart(chartPath string, settings *cli.EnvSettings) error {
	// Create action configuration
	actionConfig := new(action.Configuration)
	if err := actionConfig.Init(settings.RESTClientGetter(), settings.Namespace(), os.Getenv("HELM_DRIVER"), func(format string, v ...interface{}) {
		_, _ = fmt.Fprintf(os.Stderr, format, v...)
	}); err != nil {
		return fmt.Errorf("failed to initialize action configuration: %w", err)
	}

	// Create install action (used for templating)
	install := action.NewInstall(actionConfig)
	install.DryRun = true
	install.ReleaseName = "test-release"
	install.Replace = true
	install.ClientOnly = true
	install.APIVersions = []string{}
	install.IncludeCRDs = true

	// Load the chart
	chart, err := loader.LoadDir(chartPath)
	if err != nil {
		return fmt.Errorf("failed to load chart: %w", err)
	}

	// Run the template generation
	release, err := install.Run(chart, nil) // nil for default values
	if err != nil {
		return fmt.Errorf("failed to template chart: %w", err)
	}

	// Print the rendered templates
	fmt.Printf("---\n# Generated templates for chart: %s\n", chart.Metadata.Name)
	fmt.Print(release.Manifest)

	return nil
}
