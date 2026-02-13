package kube

import (
	"bytes"
	"errors"
	"fmt"
	"maps"
	"os"
	"os/exec"
	"path/filepath"
	"strings"

	"github.com/becloudless/becloudless/pkg/bcl"
	"github.com/becloudless/becloudless/pkg/flux"
	"github.com/becloudless/becloudless/pkg/git"
	"github.com/becloudless/becloudless/pkg/kube"
	"github.com/becloudless/becloudless/pkg/security"
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
	var adoptResources bool
	cmd := cobra.Command{
		Use:   "bootstrap",
		Short: "Bootstrap Kubernetes clusters till Flux being able to take over and apply gitops",
		Long: `The bootstrap command manually apply the necessary components, especially networking and Flux, till being able to hand over to Flux for gitops.
				  This script is re-entrant, and apply the components, like they are applied by gitops, so it can be run anytime.`,
		Aliases: []string{"boot"},
		RunE: func(cmd *cobra.Command, args []string) error {
			return Bootstrap(adoptResources)
		},
	}
	cmd.Flags().BoolVar(&adoptResources, "adopt", false, "Take ownership of existing Kubernetes resources not managed by Helm")
	return &cmd
}

func Bootstrap(adoptResources bool) error {
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

	k3sServingExists, err := secretExists(ctx, "kube-system", "k3s-serving")
	if err != nil {
		return errs.WithE(err, "Failed to check for existing k3s-serving secret")
	}

	if !k3sServingExists {
		// cilium network
		if err := applyFluxHelmReleaseWithHelm(ctx,
			filepath.Join(bcl.BCL.EmbeddedPath, "kube/apps/cilium"),
			flux.NamespacedObjectKindReference{Name: "cilium", Namespace: "kube-system"},
			envs, adoptResources); err != nil {
			return errs.WithE(err, "Failed to apply cilium")
		}

		// coredns dns
		if err := applyFluxHelmReleaseWithHelm(ctx,
			filepath.Join(bcl.BCL.EmbeddedPath, "kube/apps/coredns"),
			flux.NamespacedObjectKindReference{Name: "coredns", Namespace: "kube-system"},
			envs, adoptResources); err != nil {
			return errs.WithE(err, "Failed to apply coredns")
		}
	}

	// flux
	if err := applyFluxKustomizationWithKustomize(ctx, filepath.Join(bcl.BCL.EmbeddedPath, "kube/apps/flux"), flux.NamespacedObjectKindReference{Name: "flux", Namespace: "flux-system"}); err != nil {
		return errs.WithE(err, "Failed to bootstrap flux")
	}

	// bcl namespace
	if err := applyBclNamespace(ctx); err != nil {
		return errs.WithE(err, "Failed to ensure bcl namespace")
	}

	// flux sops key, to open secrets in git
	if err := applyInfraFluxSopsKey(ctx); err != nil {
		return errs.WithE(err, "Failed to apply flux sops key")
	}

	// git repo secret, to fetch infra repo
	if err := applyInfraGitRepoSecret(ctx); err != nil {
		return errs.WithE(err, "Failed to apply git repo secret")
	}

	// infra git repo
	if err := applyResourcesFile(ctx, "bcl/infra.gitrepo.yaml"); err != nil {
		return errs.WithE(err, "Failed to apply infra git repo")
	}

	// infra kustomization from git repo to bootstrap rest
	if err := applyResourcesFile(ctx, "bcl/infra.ks.yaml"); err != nil {
		return errs.WithE(err, "Failed to apply infra kustomization")
	}

	//
	// from there, if git is actually in the cluster, it requires more applies
	// gitea (bcl-server) + longhorm (bcl-global) + gitea-secrets + ??

	if err := applyKustomizationFolder(ctx, filepath.Join(ctx.ClusterPath, "../../../config")); err != nil {
		return errs.WithE(err, "Failed to apply infra kustomization")
	}

	if err := applyResourcesFile(ctx, filepath.Join(ctx.ClusterPath, "bcl/bcl.gitrepo.yaml")); err != nil {
		return errs.WithE(err, "Failed to apply infra kustomization")
	}

	if err := applyResourcesFile(ctx, filepath.Join(ctx.ClusterPath, "bcl/bcl-global.ks.yaml")); err != nil {
		return errs.WithE(err, "Failed to apply infra kustomization")
	}

	if err := applyResourcesFile(ctx, filepath.Join(ctx.ClusterPath, "bcl/bcl-server.ks.yaml")); err != nil {
		return errs.WithE(err, "Failed to apply infra kustomization")
	}

	return nil
}

func applyBclNamespace(ctx kube.Context) error {
	logs.Info("Applying bcl namespace")

	nsYAML := `apiVersion: v1
kind: Namespace
metadata:
  name: bcl
`
	cmd := exec.Command("kubectl", "apply", "-f", "-")
	cmd.Env = append(os.Environ(), fmt.Sprintf("KUBECONFIG=%s", ctx.KubeConfig))
	cmd.Stdin = strings.NewReader(nsYAML)
	output, err := cmd.CombinedOutput()
	if err != nil {
		return errs.WithEF(err, data.WithField("output", string(output)), "Failed to apply bcl namespace")
	}

	return nil
}

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

func applyInfraFluxSopsKey(context kube.Context) error {
	logs.Info("Applying infra's flux sops key")

	key, err := resolveAgeIdentityKey(context)
	if err != nil {
		return err
	}
	secretYAML := fmt.Sprintf(`apiVersion: v1
kind: Secret
metadata:
  name: sops-age
  namespace: bcl
stringData:
  age.agekey: %s
`, key)

	applyCmd := exec.Command("kubectl", "apply", "-f", "-")
	applyCmd.Env = append(os.Environ(), fmt.Sprintf("KUBECONFIG=%s", context.KubeConfig))
	applyCmd.Stdin = strings.NewReader(secretYAML)
	output, err := applyCmd.CombinedOutput()
	if err != nil {
		return errs.WithEF(err, data.WithField("output", string(output)), "Failed to apply sops-age secret")
	}

	return nil
}

func resolveAgeIdentityKey(context kube.Context) (string, error) {
	if os.Geteuid() == 0 {
		// Running as root, assume bootstrap on host and use host ssh private key
		_, privateKey, err := security.Ed25519PrivateKeyFileToPublicAndPrivateAgeKeys("/nix/etc/ssh/ssh_host_ed25519_key")
		return privateKey, err
	}

	// Non-root: decrypt bcl/infra.secret.yaml, extract identity, convert to age.
	sshPriv, err := readIdentitySSHPrivateKeyFromSopsSecret(context, filepath.Join(context.ClusterPath, "bcl/infra.secret.yaml"))
	if err != nil {
		return "", err
	}
	_, privateKey, err := security.Ed25519ToPublicAndPrivateAgeKeys(sshPriv)
	return privateKey, err
}

func readIdentitySSHPrivateKeyFromSopsSecret(context kube.Context, path string) ([]byte, error) {
	ageKey := ""
	if os.Geteuid() == 0 {
		_, privateKey, err := security.Ed25519PrivateKeyFileToPublicAndPrivateAgeKeys("/nix/etc/ssh/ssh_host_ed25519_key")
		if err != nil {
			return nil, errs.WithE(err, "Failed to read host ed25519 private key")
		}
		ageKey = privateKey
	}

	plaintext, err := security.DecryptSopsYAMLWithAgeKey(path, ageKey)
	if err != nil {
		return nil, err
	}

	var doc struct {
		StringData struct {
			Identity   string `yaml:"identity"`
			KnownHosts string `yaml:"known_hosts"`
		} `yaml:"stringData"`
	}
	if err := yaml.Unmarshal(plaintext, &doc); err != nil {
		return nil, errs.WithE(err, "Failed to parse decrypted yaml")
	}

	if doc.StringData.Identity == "" {
		return nil, errs.WithF(data.WithField("path", path), "Missing .stringData.identity in decrypted secret")
	}
	return []byte(doc.StringData.Identity), nil
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

func applyFluxHelmReleaseWithHelm(ctx kube.Context, resourcesPath string, objectRef flux.NamespacedObjectKindReference, envs map[string]string, adoptResources bool) error {
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
		return prepareAndApplyFluxHelmRelease(ctx, hr, resourcesPath, envs, adoptResources)

	}); err != nil {
		return errs.WithEF(err, data.WithField("folder", resourcesPath), "Failed to walk resources folder to find helm release")
	}
	if !found {
		return errs.WithF(data.WithField("name", objectRef.Name).WithField("namespace", objectRef.Namespace), "HelmRelease not found in resources")
	}
	return nil
}

func prepareAndApplyFluxHelmRelease(ctx kube.Context, hr flux.HelmRelease, resourcesPath string, envs map[string]string, adoptResources bool) error {
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
	if err := actionConfig.Init(settings.RESTClientGetter(), hr.Metadata.Namespace, os.Getenv("HELM_DRIVER"), func(format string, v ...any) {
		fmt.Printf(format+"\n", v...)
	}); err != nil {
		return errs.WithE(err, "Failed to initialize Helm action configuration")
	}

	upgrade := action.NewUpgrade(actionConfig)
	upgrade.Namespace = hr.Metadata.Namespace
	upgrade.Version = hr.Spec.Chart.Spec.Version
	if adoptResources {
		upgrade.TakeOwnership = true
	}

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
	maps.Copy(vals, processedValues)

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
			if adoptResources {
				inst.TakeOwnership = true
			}
			if _, err := inst.Run(chart, vals); err != nil {
				return errs.WithE(err, "Failed to install helm release")
			}
		} else {
			return errs.WithE(err, "Failed to upgrade helm release")
		}
	}

	return nil
}

func applyInfraGitRepoSecret(context kube.Context) error {
	path := filepath.Join(context.ClusterPath, "bcl/infra.secret.yaml")
	logs.WithField("path", path).Info("Applying infra git secret")

	ageKey := ""
	if os.Geteuid() == 0 {
		_, privateKey, err := security.Ed25519PrivateKeyFileToPublicAndPrivateAgeKeys("/nix/etc/ssh/ssh_host_ed25519_key")
		if err != nil {
			return errs.WithE(err, "Failed to read host ed25519 private key")
		}
		ageKey = privateKey
	}

	plaintext, err := security.DecryptSopsYAMLWithAgeKey(path, ageKey)
	if err != nil {
		return errs.WithEF(err, data.WithField("path", path), "Failed to decrypt infra secret")
	}

	applyCmd := exec.Command("kubectl", "apply", "-f", "-")
	applyCmd.Env = append(os.Environ(), fmt.Sprintf("KUBECONFIG=%s", context.KubeConfig))
	applyCmd.Stdin = bytes.NewReader(plaintext)
	output, err := applyCmd.CombinedOutput()
	if err != nil {
		return errs.WithEF(err, data.WithField("output", string(output)), "Failed to apply decrypted infra secret")
	}

	logs.Info("infra git secret applied")
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

func secretExists(ctx kube.Context, namespace, name string) (bool, error) {
	cmd := exec.Command("kubectl", "get", "secret", name, "-n", namespace)
	cmd.Env = append(os.Environ(), fmt.Sprintf("KUBECONFIG=%s", ctx.KubeConfig))
	if err := cmd.Run(); err != nil {
		// If kubectl returns a non-zero exit code, the secret probably does not exist.
		// Distinguish between "NotFound" and other errors by inspecting the error type.
		var exitErr *exec.ExitError
		if errors.As(err, &exitErr) {
			return false, nil
		}
		return false, err
	}
	return true, nil
}
