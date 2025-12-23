package kube

import (
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"

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
	if ctx.KubeConfig == "" {
		return errs.With("Current directory is not in a kube/cluster folder")
	}

	//repository, err := git.OpenRepository(".")
	//if err != nil {
	//	return errs.WithE(err, "Failed to open git repository")
	//}
	//config, err := GetBclConfig(repository)
	//if err != nil {
	//	return errs.WithE(err, "Failed to read BCL config")
	//}
	//envs := config.ToEnv()

	//// cilium network
	//if err := installHelmRelease(ctx,
	//	filepath.Join(bcl.BCL.EmbeddedPath, "kube/apps/cilium/cilium.helmrepo.yaml"),
	//	filepath.Join(bcl.BCL.EmbeddedPath, "kube/apps/cilium/cilium.hr.yaml"),
	//	envs); err != nil {
	//	return errs.WithE(err, "Failed to install cilium")
	//}
	//
	//// coredns dns
	//if err := installHelmRelease(ctx,
	//	filepath.Join(bcl.BCL.EmbeddedPath, "kube/apps/coredns/coredns.ocirepo.yaml"),
	//	filepath.Join(bcl.BCL.EmbeddedPath, "kube/apps/coredns/coredns.hr.yaml"),
	//	envs); err != nil {
	//	return errs.WithE(err, "Failed to install coredns")
	//}

	// flux
	if err := bootstrapFlux(ctx); err != nil {
		return errs.WithE(err, "Failed to bootstrap flux")
	}

	// flux sops key

	// git repo secret

	// git repo

	return nil
}

func installHelmRelease(ctx Context, repoPath string, hrPath string, envs map[string]string) error {
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
	settings.KubeConfig = ctx.KubeConfig

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

	processedValuesAny := substituteEnvInStructure(hr.Spec.Values, envs)
	processedValues, ok := processedValuesAny.(map[string]any)
	if !ok {
		return errs.With("Processed values are not a map[string]any")
	}
	for k, v := range processedValues {
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
	// chart, err := loader.LoadDir(chartPath)
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

func substituteEnvInStructure(value any, envs map[string]string) any {
	switch v := value.(type) {
	case map[string]any:
		res := make(map[string]any, len(v))
		for k, val := range v {
			res[k] = substituteEnvInStructure(val, envs)
		}
		return res
	case []any:
		res := make([]any, len(v))
		for i, val := range v {
			res[i] = substituteEnvInStructure(val, envs)
		}
		return res
	case string:
		res := v
		for k, v2 := range envs {
			if k == "" {
				continue
			}
			placeholder := "${" + k + "}"
			if strings.Contains(res, placeholder) {
				res = strings.ReplaceAll(res, placeholder, v2)
			}
		}
		return res
	default:
		return v
	}
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

func bootstrapFlux(ctx Context) error {
	// Read the embedded Flux Kustomization spec
	fluxKsPath := filepath.Join(bcl.BCL.EmbeddedPath, "kube/apps/flux/flux.ks.yaml")
	content, err := os.ReadFile(fluxKsPath)
	if err != nil {
		return errs.WithEF(err, data.WithField("path", fluxKsPath), "Failed to read flux Kustomization template")
	}

	// Parse the Flux Kustomization so we can translate patches into kustomize format
	var fluxKs struct {
		Metadata struct {
			Namespace string `yaml:"namespace"`
		} `yaml:"metadata"`
		Spec struct {
			Patches []struct {
				Target struct {
					Kind      string `yaml:"kind"`
					Name      string `yaml:"name"`
					Namespace string `yaml:"namespace"`
				} `yaml:"target"`
				Patch string `yaml:"patch"`
			} `yaml:"patches"`
		} `yaml:"spec"`
	}
	if err := yaml.Unmarshal(content, &fluxKs); err != nil {
		return errs.WithE(err, "Failed to parse flux Kustomization")
	}

	// Build a temporary directory for the generated kustomization
	tmpDir, err := os.MkdirTemp("", "bcl-flux-")
	if err != nil {
		return errs.WithE(err, "Failed to create temp directory for flux kustomization")
	}
	//defer func() {
	//	_ = os.RemoveAll(tmpDir)
	//}()

	// Write patches as separate files and build a kustomization.yaml that applies them
	kustomization := struct {
		APIVersion string   `yaml:"apiVersion"`
		Kind       string   `yaml:"kind"`
		Resources  []string `yaml:"resources,omitempty"`
		Patches    []struct {
			Path   string `yaml:"path"`
			Target struct {
				Kind      string `yaml:"kind,omitempty"`
				Name      string `yaml:"name,omitempty"`
				Namespace string `yaml:"namespace,omitempty"`
			} `yaml:"target"`
		} `yaml:"patches,omitempty"`
	}{
		APIVersion: "kustomize.config.k8s.io/v1beta1",
		Kind:       "Kustomization",
	}

	for i, p := range fluxKs.Spec.Patches {
		patchFile := fmt.Sprintf("patch-%d.yaml", i)
		if err := os.WriteFile(filepath.Join(tmpDir, patchFile), []byte(p.Patch), 0o644); err != nil {
			return errs.WithEF(err, data.WithField("path", patchFile), "Failed to write flux patch file")
		}
		entry := struct {
			Path   string `yaml:"path"`
			Target struct {
				Kind      string `yaml:"kind,omitempty"`
				Name      string `yaml:"name,omitempty"`
				Namespace string `yaml:"namespace,omitempty"`
			} `yaml:"target"`
		}{}
		entry.Path = patchFile
		entry.Target.Kind = p.Target.Kind
		entry.Target.Name = p.Target.Name
		entry.Target.Namespace = p.Target.Namespace
		kustomization.Patches = append(kustomization.Patches, entry)
	}

	kustomContent, err := yaml.Marshal(&kustomization)
	if err != nil {
		return errs.WithE(err, "Failed to marshal generated kustomization")
	}

	kustomizationPath := filepath.Join(tmpDir, "kustomization.yaml")
	if err := os.WriteFile(kustomizationPath, kustomContent, 0o644); err != nil {
		return errs.WithEF(err, data.WithField("path", kustomizationPath), "Failed to write generated kustomization")
	}

	logs.WithField("path", kustomizationPath).Info("Applying translated flux kustomization")

	cmd := exec.Command("kubectl", "apply", "-k", tmpDir)
	cmd.Env = append(os.Environ(), fmt.Sprintf("KUBECONFIG=%s", ctx.KubeConfig))
	output, err := cmd.CombinedOutput()
	if err != nil {
		return errs.WithEF(err, data.WithField("output", string(output)), "Failed to apply translated flux kustomization")
	}

	return nil
}
