package chart

import (
	"github.com/becloudless/becloudless/pkg/kube/helm"
	"github.com/n0rad/go-erlog/errs"
	"github.com/n0rad/go-erlog/logs"
	"github.com/spf13/cobra"
	"helm.sh/helm/v3/pkg/cli"
)

func buildCmd() *cobra.Command {
	var path string
	var kubeVersion string
	var validate bool

	cmd := &cobra.Command{
		Use:   "build",
		Args:  cobra.ExactArgs(0),
		Short: "Build a helm chart",
		RunE: func(cmd *cobra.Command, args []string) error {
			chart, err := helm.OpenChart(path, cli.New())
			if err != nil {
				return errs.WithE(err, "Failed to open chart")
			}

			if err := chart.UpdateDependencies(); err != nil {
				return errs.WithE(err, "Failed to update chart dependencies")
			}

			// running unit tests
			if err := chart.RunUnitTests(); err != nil {
				return errs.WithE(err, "Failed to run chart unit tests")
			}

			// running integration tests
			if err := chart.RunCITests(kubeVersion, validate); err != nil {
				return errs.WithE(err, "Failed to run chart CI tests")
			}

			logs.WithField("path", path).Info("Chart build completed successfully")
			return nil
		},
	}

	cmd.Flags().StringVar(&path, "path", ".", "Chart directory path")
	cmd.Flags().StringVar(&kubeVersion, "kube-version", "1.31.0", "Kubernetes version used for Capabilities.KubeVersion")
	cmd.Flags().BoolVar(&validate, "validate", false, "Validate CI-rendered manifests against the Kubernetes cluster you are currently pointing at via server-side dry-run (requires a reachable cluster); same validation performed on an install")

	return cmd
}
