package kube

import (
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"

	"github.com/becloudless/becloudless/pkg/bcl"
	"github.com/becloudless/becloudless/pkg/flux"
	"github.com/becloudless/becloudless/pkg/git"
	"github.com/becloudless/becloudless/pkg/kube"
	"github.com/n0rad/go-erlog/data"
	"github.com/n0rad/go-erlog/errs"
	"github.com/n0rad/go-erlog/logs"
	"github.com/spf13/cobra"
	"gopkg.in/yaml.v3"
	"helm.sh/helm/v3/pkg/action"
	"helm.sh/helm/v3/pkg/chart/loader"
	"helm.sh/helm/v3/pkg/cli"
	"helm.sh/helm/v3/pkg/cli/values"
	"helm.sh/helm/v3/pkg/getter"
	"helm.sh/helm/v3/pkg/repo"
	"helm.sh/helm/v3/pkg/storage/driver"
)

func kubeBootstrapCmd() *cobra.Command {
	cmd := cobra.Command{
		Use:   "bootstrap",
		Short: "Bootstrap Kubernetes clusters till Flux being able to take over and apply gitops",
		Long: `The bootstrap command manually apply the necessary components, especially networking and Flux, till being able to hand over to Flux for gitops.
				  This script is re-entrant, and apply the components, like they are applied by gitops, so it can be run anytime.`,
		Aliases: []string{"boot"},
		RunE: func(cmd *cobra.Command, args []string) error {
			return Bootstrap()
		},
	}
	return &cmd
}

func Bootstrap() error {
	ctx, err := kube.GetContext(".")
	if err != nil {
		return errs.WithE(err, "Cannot find kube cluster context. Are you in a cluster folder?")
	}
	if ctx.KubeConfig == "" {
		return errs.With("Current directory is not in a kube/cluster folder")
	}

	repository, err := git.OpenRepository(".")
	if err != nil {
		return errs.WithE(err, "Failed to open git repository")
	}
	config, err := kube.GetBclConfig(repository)
	if err != nil {
		return errs.WithE(err, "Failed to read BCL config")
	}
	envs := config.ToEnv()

	// cilium network
	if err := applyFluxHelmReleaseWithHelm(ctx,
		filepath.Join(bcl.BCL.EmbeddedPath, "kube/apps/cilium"),
		flux.NamespacedObjectKindReference{Name: "cilium", Namespace: "kube-system"},
		envs); err != nil {
		return errs.WithE(err, "Failed to apply cilium")
	}

	// coredns dns
	if err := applyFluxHelmReleaseWithHelm(ctx,
		filepath.Join(bcl.BCL.EmbeddedPath, "kube/apps/coredns"),
		flux.NamespacedObjectKindReference{Name: "coredns", Namespace: "kube-system"},
		envs); err != nil {
		return errs.WithE(err, "Failed to apply coredns")
	}

	// flux
	if err := applyFluxKustomizationWithKustomize(ctx, filepath.Join(bcl.BCL.EmbeddedPath, "kube/apps/flux"), flux.NamespacedObjectKindReference{Name: "flux", Namespace: "flux-system"}); err != nil {
		return errs.WithE(err, "Failed to bootstrap flux")
	}

	// flux sops key

	// git repo secret

	// git repo

	return nil
}

func applyFluxKustomizationWithKustomize(ctx kube.Context, resourcesPath string, objectRef flux.NamespacedObjectKindReference) error {
	found := false
	if err := filepath.WalkDir(resourcesPath, func(path string, d os.DirEntry, err error) error {
		if err != nil {
			return err
		}
		if found {
			return filepath.SkipAll
		}
		if d.IsDir() {
			return nil
		}
		content, err := os.ReadFile(path)
		if err != nil {
			return errs.WithEF(err, data.WithField("path", path), "Failed to read file")
		}
		var fluxKs flux.Kustomization

		if err := yaml.Unmarshal(content, &fluxKs); err != nil {
			return errs.WithE(err, "Failed to parse flux Kustomization patches")
		}

		if !(fluxKs.Kind == "Kustomization" &&
			fluxKs.Metadata.Name == objectRef.Name &&
			fluxKs.Metadata.Namespace == objectRef.Namespace) {
			return nil
		}

		found = true
		return prepareAndApplyFluxKustomization(ctx, fluxKs, resourcesPath)

	}); err != nil {
		return errs.WithEF(err, data.WithField("folder", resourcesPath), "Failed to walk resources folder to find flux kustomization")
	}
	if !found {
		return errs.WithF(data.WithField("name", objectRef.Name).WithField("namespace", objectRef.Namespace), "Kustomization not found in resources")
	}
	return nil
}

func prepareAndApplyFluxKustomization(ctx kube.Context, ks flux.Kustomization, resourcesFolder string) error {
	_, ref, err := flux.GetRepositoryUrlAndRef(resourcesFolder, ks.Spec.SourceRef.DeduceNamespaceFromMetadata(ks.Metadata))
	if err != nil {
		return err
	}

	// Build a temporary directory for the generated kustomization
	tmpDir, err := os.MkdirTemp("", "bcl-flux-")
	if err != nil {
		return errs.WithE(err, "Failed to create temp directory for flux kustomization")
	}
	defer os.RemoveAll(tmpDir)

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

	// Add the core Flux manifests resource, using the version from the OCIRepository
	kustomization.Resources = append(kustomization.Resources, fmt.Sprintf("github.com/fluxcd/flux2/manifests/install?ref=%s", ref))

	for i, p := range ks.Spec.Patches {
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

	logs.WithField("ref", ref).Info("Applying flux kustomization")

	cmd := exec.Command("kubectl", "apply", "-k", tmpDir)
	cmd.Env = append(os.Environ(), fmt.Sprintf("KUBECONFIG=%s", ctx.KubeConfig))
	output, err := cmd.CombinedOutput()
	if err != nil {
		return errs.WithEF(err, data.WithField("output", string(output)), "Failed to apply kustomization")
	}

	return nil
}

func applyFluxHelmReleaseWithHelm(ctx kube.Context, resourcesPath string, objectRef flux.NamespacedObjectKindReference, envs map[string]string) error {
	found := false
	if err := filepath.WalkDir(resourcesPath, func(path string, d os.DirEntry, err error) error {
		if err != nil {
			return err
		}
		if found {
			return filepath.SkipAll
		}
		if d.IsDir() {
			return nil
		}
		content, err := os.ReadFile(path)
		if err != nil {
			return errs.WithEF(err, data.WithField("path", path), "Failed to read file")
		}

		var hr flux.HelmRelease

		if err := yaml.Unmarshal(content, &hr); err != nil {
			return errs.WithE(err, "Failed to parse flux Kustomization patches")
		}

		if !(hr.Kind == "HelmRelease" &&
			hr.Metadata.Name == objectRef.Name &&
			hr.Metadata.Namespace == objectRef.Namespace) {
			return nil
		}

		found = true
		return prepareAndApplyFluxHelmRelease(ctx, hr, resourcesPath, envs)

	}); err != nil {
		return errs.WithEF(err, data.WithField("folder", resourcesPath), "Failed to walk resources folder to find helm release")
	}
	if !found {
		return errs.WithF(data.WithField("name", objectRef.Name).WithField("namespace", objectRef.Namespace), "HelmRelease not found in resources")
	}
	return nil
}

func prepareAndApplyFluxHelmRelease(ctx kube.Context, hr flux.HelmRelease, resourcesPath string, envs map[string]string) error {
	settings := cli.New()
	settings.KubeConfig = ctx.KubeConfig

	// repo
	repoUrl, _, err := flux.GetRepositoryUrlAndRef(resourcesPath, hr.Spec.Chart.Spec.SourceRef.DeduceNamespaceFromMetadata(hr.Metadata))
	if err != nil {
		return errs.WithE(err, "Failed to read helmRepo file to get chart")
	}
	chartRepo, err := repo.NewChartRepository(&repo.Entry{Name: hr.Spec.Chart.Spec.SourceRef.Name, URL: repoUrl}, getter.All(settings))
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
		Info("Applying helm release")

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
