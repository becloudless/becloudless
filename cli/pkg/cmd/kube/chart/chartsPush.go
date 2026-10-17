package chart

import (
	"os"

	"github.com/becloudless/becloudless/pkg/docker"
	"github.com/becloudless/becloudless/pkg/git"
	"github.com/becloudless/becloudless/pkg/kube/helm"
	"github.com/n0rad/go-erlog/errs"
	"github.com/n0rad/go-erlog/logs"
	"github.com/spf13/cobra"
	"helm.sh/helm/v3/pkg/cli"
)

// RemoteFromGitRepository deduces the OCI remote charts are pushed to from the origin of the git repository,
// e.g. oci://ghcr.io/<owner>/charts
func RemoteFromGitRepository(repo *git.Repository) (string, error) {
	url, err := repo.GetRemoteOriginURL()
	if err != nil {
		return "", errs.WithE(err, "Failed to get remote origin URL")
	}
	registry, _, err := docker.GetRegistryAndRepositoryFromGitUrl(url)
	if err != nil {
		return "", errs.WithE(err, "Failed to deduce registry from git URL")
	}
	return "oci://" + registry + "/charts", nil
}

// PushChart updates dependencies of the chart at path, then packages and pushes it to an OCI registry.
// When opts.Remote is empty, it is deduced from the git repository containing the chart.
func PushChart(path string, opts helm.PushOptions) error {
	if opts.Remote == "" {
		repo, err := git.OpenRepository(path)
		if err != nil {
			return errs.WithE(err, "Failed to open git repository to deduce remote")
		}
		opts.Remote, err = RemoteFromGitRepository(repo)
		if err != nil {
			return err
		}
	}

	chart, err := helm.OpenChart(path, cli.New())
	if err != nil {
		return errs.WithE(err, "Failed to open chart")
	}

	if err := chart.UpdateDependencies(); err != nil {
		return errs.WithE(err, "Failed to update chart dependencies")
	}

	if opts.Password == "" {
		opts.Password = os.Getenv("HELM_REGISTRY_PASSWORD")
	}

	if err := chart.Push(opts); err != nil {
		return errs.WithE(err, "Failed to push chart")
	}

	logs.WithField("path", path).WithField("remote", opts.Remote).Info("Chart pushed successfully")
	return nil
}

func pushCmd() *cobra.Command {
	var path string
	var opts helm.PushOptions

	cmd := &cobra.Command{
		Use:   "push",
		Args:  cobra.ExactArgs(0),
		Short: "Package a helm chart and push it to an OCI registry",
		RunE: func(cmd *cobra.Command, args []string) error {
			return PushChart(path, opts)
		},
	}

	cmd.Flags().StringVar(&path, "path", ".", "Chart directory path")
	cmd.Flags().StringVar(&opts.Remote, "remote", "", "OCI registry location to push the chart to (default: deduced from the git repository origin, as oci://<registry>/<owner>/charts)")
	cmd.Flags().StringVar(&opts.Version, "version", "", "Chart version (default: generated from date and git state, like bcl: 1.YYMMDD.HHMM-H<hash>)")
	cmd.Flags().StringVar(&opts.AppVersion, "app-version", "", "Override the chart appVersion")
	cmd.Flags().StringVar(&opts.Username, "username", "", "Registry username (defaults to credentials from 'helm registry login')")
	cmd.Flags().StringVar(&opts.Password, "password", "", "Registry password (defaults to $HELM_REGISTRY_PASSWORD, then 'helm registry login' credentials)")
	cmd.Flags().BoolVar(&opts.PlainHTTP, "plain-http", false, "Use plain HTTP to talk to the registry")

	return cmd
}
