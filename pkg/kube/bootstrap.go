package kube

import (
	"errors"
	"fmt"
	"os"
	"path/filepath"

	"github.com/becloudless/becloudless/pkg/bcl"
	"github.com/n0rad/go-erlog/data"
	"github.com/n0rad/go-erlog/errs"
	"github.com/n0rad/go-erlog/logs"
	"gopkg.in/yaml.v3"
	"helm.sh/helm/v3/pkg/action"
	"helm.sh/helm/v3/pkg/chart/loader"
	"helm.sh/helm/v3/pkg/cli"
	"helm.sh/helm/v3/pkg/cli/values"
	"helm.sh/helm/v3/pkg/getter"
	"helm.sh/helm/v3/pkg/repo"
	"helm.sh/helm/v3/pkg/storage/driver"
)

func Bootstrap() error {
	ctx, err := GetContext(".")
	if err != nil {
		return errs.WithE(err, "Cannot find kube cluster context. Are you in a cluster folder?")
	}
	if ctx.KubeContext == "" {
		return errs.With("Current directory is not in a kube/cluster folder")
	}

	// cilium network
	if err := installHelmRelease(ctx,
		filepath.Join(bcl.BCL.EmbeddedPath, "kube/apps/cilium/cilium.helmrepo.yaml"),
		filepath.Join(bcl.BCL.EmbeddedPath, "kube/apps/cilium/cilium.hr.yaml")); err != nil {
		return errs.WithE(err, "Failed to install cilium")
	}

	// coredns dns
	if err := installHelmRelease(ctx,
		filepath.Join(bcl.BCL.EmbeddedPath, "kube/apps/coredns/coredns.ocirepo.yaml"),
		filepath.Join(bcl.BCL.EmbeddedPath, "kube/apps/coredns/coredns.hr.yaml")); err != nil {
		return errs.WithE(err, "Failed to install coredns")
	}

	// flux

	// flux sops key

	// git repo secret

	// git repo

	return nil
}

func installHelmRelease(ctx Context, repoPath string, hrPath string) error {
	content, err := os.ReadFile(hrPath)
	if err != nil {
		return errs.WithEF(err, data.WithField("path", hrPath), "Failed to read HelmRelease file")
	}

	var hr struct {
		Metadata struct {
			Name      string `yaml:"name"`
			Namespace string `yaml:"namespace"`
		} `yaml:"metadata"`
		Spec struct {
			Chart struct {
				Spec struct {
					Chart   string `yaml:"chart"`
					Version string `yaml:"version"`
				} `yaml:"spec"`
			} `yaml:"chart"`
			Values map[string]any `yaml:"values"`
		} `yaml:"spec"`
	}

	if err := yaml.Unmarshal(content, &hr); err != nil {
		return errs.WithE(err, "Failed to parse HelmRelease manifest")
	}

	settings := cli.New()
	settings.KubeConfig = ctx.KubeContext

	// repo
	repoName, repoUrl, err := getHelmRepositoryURL(repoPath)
	if err != nil {
		return errs.WithE(err, "Failed to read helmRepo file to get chart")
	}
	chartRepo, err := repo.NewChartRepository(&repo.Entry{Name: repoName, URL: repoUrl}, getter.All(settings))
	if err != nil {
		return errs.WithE(err, "Failed to create chart repository client")
	}
	if _, err := chartRepo.DownloadIndexFile(); err != nil {
		return errs.WithE(err, "Failed to download Helm repo index")
	}

	actionConfig := new(action.Configuration)
	if err := actionConfig.Init(settings.RESTClientGetter(), hr.Metadata.Namespace, os.Getenv("HELM_DRIVER"), func(format string, v ...interface{}) {
		fmt.Printf(format+"\n", v...)
	}); err != nil {
		return errs.WithE(err, "Failed to initialize Helm action configuration")
	}

	upgrade := action.NewUpgrade(actionConfig)
	upgrade.Namespace = hr.Metadata.Namespace
	upgrade.Version = hr.Spec.Chart.Spec.Version

	// Build values from the HR spec
	p := values.Options{}
	vals, err := p.MergeValues(getter.All(settings))
	if err != nil {
		return errs.WithE(err, "Failed to build Helm values")
	}

	// Merge HR values into Helm values map
	for k, v := range hr.Spec.Values {
		vals[k] = v
	}

	chartPathOptions := &action.ChartPathOptions{
		RepoURL: repoUrl,
		Version: hr.Spec.Chart.Spec.Version,
	}
	chartPath, err := chartPathOptions.LocateChart(hr.Spec.Chart.Spec.Chart, settings)
	if err != nil {
		return errs.WithE(err, "Failed to locate helm chart")
	}

	chart, err := loader.Load(chartPath)
	if err != nil {
		return errs.WithE(err, "Failed to load helm chart")
	}

	logs.WithField("chart", chart.Metadata.Name).
		WithField("version", chart.Metadata.Version).
		Info("Installing helm release")

	if _, err := upgrade.Run(hr.Metadata.Name, chart, vals); err != nil {
		if errors.Is(err, driver.ErrReleaseNotFound) ||
			errors.Is(err, driver.ErrNoDeployedReleases) {
			inst := action.NewInstall(actionConfig)
			inst.ReleaseName = hr.Metadata.Name
			inst.Namespace = hr.Metadata.Namespace
			inst.Version = hr.Spec.Chart.Spec.Version
			if _, err := inst.Run(chart, vals); err != nil {
				return errs.WithE(err, "Failed to install helm release")
			}
		} else {
			return errs.WithE(err, "Failed to upgrade helm release")
		}
	}

	return nil
}

func getHelmRepositoryURL(helmRepositoryPath string) (string, string, error) {
	content, err := os.ReadFile(helmRepositoryPath)
	if err != nil {
		return "", "", errs.WithEF(err, data.WithField("path", helmRepositoryPath), "Failed to read HelmRelease file")
	}

	var helmRepo struct {
		Metadata struct {
			Name      string `yaml:"name"`
			Namespace string `yaml:"namespace"`
		} `yaml:"metadata"`
		Spec struct {
			Url string `yaml:"url"`
		} `yaml:"spec"`
	}

	if err := yaml.Unmarshal(content, &helmRepo); err != nil {
		return "", "", errs.WithEF(err, data.WithField("path", helmRepositoryPath), "Failed to parse Helm repository")
	}
	return helmRepo.Metadata.Name, helmRepo.Spec.Url, nil
}
