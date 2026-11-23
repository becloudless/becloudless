package kube

import (
	"errors"
	"fmt"
	"maps"
	"os"
	"os/exec"
	"path/filepath"

	"github.com/becloudless/becloudless/pkg/flux"
	"github.com/becloudless/becloudless/pkg/kube"
	"github.com/n0rad/go-erlog/data"
	"github.com/n0rad/go-erlog/errs"
	"github.com/n0rad/go-erlog/logs"
	"gopkg.in/yaml.v3"
	"helm.sh/helm/v4/pkg/action"
	helmchart "helm.sh/helm/v4/pkg/chart"
	"helm.sh/helm/v4/pkg/chart/loader"
	"helm.sh/helm/v4/pkg/cli"
	"helm.sh/helm/v4/pkg/cli/values"
	"helm.sh/helm/v4/pkg/getter"
	helmkube "helm.sh/helm/v4/pkg/kube"
	repo "helm.sh/helm/v4/pkg/repo/v1"
	"helm.sh/helm/v4/pkg/storage/driver"
)

func applyResourcesFile(ctx kube.Context, file string) error {
	applyCmd := exec.Command("kubectl", "apply", "-f", file)
	applyCmd.Env = append(os.Environ(), fmt.Sprintf("KUBECONFIG=%s", ctx.KubeConfig))
	output, err := applyCmd.CombinedOutput()
	if err != nil {
		return errs.WithEF(err, data.WithField("output", string(output)).WithField("file", file), "Failed to apply infra kustomization manifest")
	}
	return nil
}

func applyKustomizationFolder(ctx kube.Context, path string) error {
	cmd := exec.Command("kubectl", "apply", "-k", path)
	cmd.Env = append(os.Environ(), fmt.Sprintf("KUBECONFIG=%s", ctx.KubeConfig))
	output, err := cmd.CombinedOutput()
	if err != nil {
		return errs.WithEF(err, data.WithField("output", string(output)), "Failed to apply kustomization")
	}

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
	defer func() {
		if err := os.RemoveAll(tmpDir); err != nil {
			logs.WithField("dir", tmpDir).WithField("error", err.Error()).Info("Failed to remove temp dir")
		}
	}()

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
	return applyKustomizationFolder(ctx, tmpDir)
}

func applyFluxHelmReleaseWithHelm(ctx kube.Context, resourcesPath string, objectRef flux.NamespacedObjectKindReference, adoptResources bool) error {
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
		return prepareAndApplyFluxHelmRelease(ctx, hr, resourcesPath, adoptResources)

	}); err != nil {
		return errs.WithEF(err, data.WithField("folder", resourcesPath), "Failed to walk resources folder to find helm release")
	}
	if !found {
		return errs.WithF(data.WithField("name", objectRef.Name).WithField("namespace", objectRef.Namespace), "HelmRelease not found in resources")
	}
	return nil
}

func prepareAndApplyFluxHelmRelease(ctx kube.Context, hr flux.HelmRelease, resourcesPath string, adoptResources bool) error {
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
	if err := actionConfig.Init(settings.RESTClientGetter(), hr.Metadata.Namespace, os.Getenv("HELM_DRIVER")); err != nil {
		return errs.WithE(err, "Failed to initialize Helm action configuration")
	}

	upgrade := action.NewUpgrade(actionConfig)
	upgrade.Namespace = hr.Metadata.Namespace
	upgrade.Version = hr.Spec.Chart.Spec.Version
	// do not wait for the resources to be ready: cilium and coredns cannot be ready before the whole bootstrap is done
	upgrade.WaitStrategy = helmkube.HookOnlyStrategy
	// the release may already be managed by the helm-controller of flux: the bootstrap takes over the fields it conflicts on
	upgrade.ForceConflicts = true
	if adoptResources {
		upgrade.TakeOwnership = true
	}

	// Build values from the HR spec
	p := values.Options{}
	vals, err := p.MergeValues(getter.All(settings))
	if err != nil {
		return errs.WithE(err, "Failed to build Helm values")
	}

	maps.Copy(vals, hr.Spec.Values)

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

	chartAc, err := helmchart.NewAccessor(chart)
	if err != nil {
		return errs.WithE(err, "Failed to create chart accessor")
	}
	chartVersion, _ := chartAc.MetadataAsMap()["Version"].(string)
	logs.WithField("chart", chartAc.Name()).
		WithField("version", chartVersion).
		Info("Applying helm release")

	// the manifest of the revision to upgrade, to know what the upgrade changes (none when the release is not installed yet)
	previousManifest := ""
	if previous, err := action.NewGet(actionConfig).Run(hr.Metadata.Name); err == nil {
		if previousManifest, err = releaseManifest(previous); err != nil {
			return err
		}
	}

	upgraded, err := upgrade.Run(hr.Metadata.Name, chart, vals)
	if err == nil {
		manifest, err := releaseManifest(upgraded)
		if err != nil {
			return err
		}
		return restartReleaseWorkloads(ctx, hr.Metadata.Namespace, previousManifest, manifest)
	}

	if !errors.Is(err, driver.ErrReleaseNotFound) && !errors.Is(err, driver.ErrNoDeployedReleases) {
		return errs.WithE(err, "Failed to upgrade helm release")
	}

	inst := action.NewInstall(actionConfig)
	inst.ReleaseName = hr.Metadata.Name
	inst.Namespace = hr.Metadata.Namespace
	inst.Version = hr.Spec.Chart.Spec.Version
	inst.WaitStrategy = helmkube.HookOnlyStrategy
	inst.ForceConflicts = true
	if adoptResources {
		inst.TakeOwnership = true
	}
	if _, err := inst.Run(chart, vals); err != nil {
		return errs.WithE(err, "Failed to install helm release")
	}

	return nil
}
