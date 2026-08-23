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

			// running integration tests
			if err := chart.RunCITests(); err != nil {
				return errs.WithE(err, "Failed to run chart CI tests")
			}

			logs.WithField("path", path).Info("Chart build completed successfully")
			return nil
		},
	}

	cmd.Flags().StringVar(&path, "path", ".", "Chart directory path")
	cmd.Flags().StringVar(&kubeVersion, "kube-version", "1.31.0", "Kubernetes version used for Capabilities.KubeVersion")

	return cmd
}
