package kube

import (
	"bytes"
	"errors"
	"fmt"
	"io"
	"net"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strings"

	"github.com/becloudless/becloudless/pkg/bcl"
	"github.com/becloudless/becloudless/pkg/cmd/flags"
	"github.com/becloudless/becloudless/pkg/flux"
	"github.com/becloudless/becloudless/pkg/kube"
	bclhelm "github.com/becloudless/becloudless/pkg/kube/helm"
	"github.com/becloudless/becloudless/pkg/system/runner"
	"github.com/n0rad/go-erlog/data"
	"github.com/n0rad/go-erlog/errs"
	"github.com/n0rad/go-erlog/logs"
	"github.com/spf13/cobra"
	"gopkg.in/yaml.v3"
)

const (
	bclChartsFolder      = "assets/kube/charts" // embedded in the binary, extracted under bcl.BCL.EmbeddedPath
	appsChartName        = "apps"
	appChartPrefix       = "app-"
	clusterAppsHrFile    = "apps/apps.hr.yaml"
	defaultAppsNamespace = "apps"
	remoteKubeconfig     = "/etc/kubernetes/admin.conf"
	apiServerPort        = "8443"
)

type bootstrapRemoteOptions struct {
	ssh            runner.SshConnectionConfig
	group          string
	kubeVersion    string
	adoptResources bool
}

func kubeBootstrapCmd() *cobra.Command {
	opts := bootstrapRemoteOptions{}
	cmd := cobra.Command{
		Use:   "bootstrap",
		Short: "Fetch the cluster credentials from a server and apply the minimal apps resources extracted from the app charts",
		Long: `Fetch the kubeconfig of the cluster from a server through ssh, then render the apps chart with the values of the cluster
(apps/apps.hr.yaml) restricted to the apps of the minimal group, render each of these app charts, and apply the resources
flux needs to start: namespaces, helm releases coming from helm repositories (ex: cilium, coredns) and the flux installation.
Everything else is left to flux once it runs. This command is re-entrant.`,
		Args: cobra.ExactArgs(0),
		RunE: func(cmd *cobra.Command, args []string) error {
			return BootstrapRemote(opts)
		},
	}
	flags.WithSSHRemoteFlags(&cmd, &opts.ssh)
	cmd.Flags().StringVar(&opts.group, "group", "minimal", "Group of apps to apply")
	cmd.Flags().StringVar(&opts.kubeVersion, "kube-version", "1.31.0", "Kubernetes version used for Capabilities.KubeVersion when rendering the charts")
	cmd.Flags().BoolVar(&opts.adoptResources, "adopt", false, "Take ownership of existing Kubernetes resources not managed by Helm")
	_ = cmd.MarkFlagRequired("host")
	return &cmd
}

func BootstrapRemote(opts bootstrapRemoteOptions) error {
	ctx, err := kube.GetContext(".")
	if err != nil {
		return errs.WithE(err, "Cannot find kube cluster context. Are you in a cluster folder?")
	}
	if ctx.KubeConfig == "" {
		return errs.With("Current directory is not in a kube/cluster folder")
	}

	if err := fetchKubeconfig(ctx.KubeConfig, opts); err != nil {
		return errs.WithE(err, "Failed to fetch the kubeconfig")
	}

	apps, gitRepositories, err := renderGroupApps(ctx, opts)
	if err != nil {
		return errs.WithE(err, "Failed to render the apps of the group")
	}

	if err := applyRenderedApps(ctx, apps, opts.adoptResources); err != nil {
		return err
	}

	return applyBcl(ctx, gitRepositories)
}

// applyBcl hands over to flux: the git repositories of the apps chart with their namespaces, and the apps helm release of the cluster.
func applyBcl(ctx kube.Context, gitRepositories []map[string]any) error {
	if err := waitFluxCRDs(ctx); err != nil {
		return errs.WithE(err, "Failed to wait for the flux CRDs")
	}

	appsHr, err := readAppsHelmRelease(ctx)
	if err != nil {
		return err
	}

	namespaces := []map[string]any{{
		"apiVersion": "v1",
		"kind":       "Namespace",
		"metadata":   map[string]any{"name": appsHr.Metadata.Namespace},
	}}
	var repositories []map[string]any
	for _, doc := range gitRepositories {
		if doc["kind"] == "Namespace" {
			namespaces = append(namespaces, doc)
		} else {
			repositories = append(repositories, doc)
		}
	}
	if err := applyNamespaces(ctx, namespaces); err != nil {
		return errs.WithE(err, "Failed to apply the namespaces of the apps helm release and of the git repositories")
	}
	if err := applyDocs(ctx, repositories, "git repositories"); err != nil {
		return errs.WithE(err, "Failed to apply the git repositories")
	}

	logs.WithField("file", clusterAppsHrFile).Info("Applying the apps helm release")
	if err := applyResourcesFile(ctx, filepath.Join(ctx.ClusterPath, clusterAppsHrFile)); err != nil {
		return errs.WithEF(err, data.WithField("file", clusterAppsHrFile), "Failed to apply the apps helm release")
	}
	return nil
}

// waitFluxCRDs waits for the CRDs of the resources applied to hand over to flux, since flux was just installed.
func waitFluxCRDs(ctx kube.Context) error {
	cmd := exec.Command("kubectl", "wait", "--for=condition=Established", "--timeout=120s",
		"crd/gitrepositories.source.toolkit.fluxcd.io",
		"crd/helmreleases.helm.toolkit.fluxcd.io")
	cmd.Env = append(os.Environ(), fmt.Sprintf("KUBECONFIG=%s", ctx.KubeConfig))
	if output, err := cmd.CombinedOutput(); err != nil {
		return errs.WithEF(err, data.WithField("output", string(output)), "Flux CRDs are not established")
	}
	return nil
}

// fetchKubeconfig reads the kubeconfig on the server and writes it to destination.
func fetchKubeconfig(destination string, opts bootstrapRemoteOptions) error {
	logs.WithField("host", opts.ssh.Host).WithField("path", remoteKubeconfig).Info("Fetching kubeconfig")
	sshRunner, err := runner.NewSshRunner(&opts.ssh)
	if err != nil {
		return errs.WithEF(err, data.WithField("host", opts.ssh.Host), "Failed to connect to the server")
	}
	kubeconfig, err := sshRunner.ExecCmdGetStdout("sudo", "cat", remoteKubeconfig)
	if err != nil {
		return errs.WithEF(err, data.WithField("host", opts.ssh.Host).WithField("path", remoteKubeconfig), "Failed to read the kubeconfig through ssh")
	}

	content, err := rewriteKubeconfigServer([]byte(kubeconfig+"\n"), opts.ssh.Host)
	if err != nil {
		return err
	}

	if err := os.MkdirAll(filepath.Dir(destination), 0o700); err != nil {
		return errs.WithEF(err, data.WithField("path", filepath.Dir(destination)), "Failed to create kubeconfig folder")
	}
	if err := os.WriteFile(destination, content, 0o600); err != nil {
		return errs.WithEF(err, data.WithField("path", destination), "Failed to write kubeconfig")
	}
	logs.WithField("path", destination).Info("Kubeconfig written")
	return nil
}

// rewriteKubeconfigServer sets the API url of the clusters to https://<serverHost>:8443,
// since the kubeconfig of a control plane node targets itself.
func rewriteKubeconfigServer(content []byte, serverHost string) ([]byte, error) {
	var config map[string]any
	if err := yaml.Unmarshal(content, &config); err != nil {
		return nil, errs.WithE(err, "Failed to parse the kubeconfig")
	}

	clusters, _ := config["clusters"].([]any)
	for _, c := range clusters {
		entry, _ := c.(map[string]any)
		cluster, _ := entry["cluster"].(map[string]any)
		if cluster == nil {
			continue
		}
		cluster["server"] = "https://" + net.JoinHostPort(serverHost, apiServerPort)
	}

	result, err := yaml.Marshal(config)
	if err != nil {
		return nil, errs.WithE(err, "Failed to marshal the kubeconfig")
	}
	return result, nil
}

type renderedApp struct {
	name string
	docs []map[string]any
}

// appsHelmRelease is the apps helm release of the cluster.
type appsHelmRelease struct {
	Metadata flux.Metadata `yaml:"metadata"`
	Spec     struct {
		Values map[string]any `yaml:"values"`
	} `yaml:"spec"`
}

// readAppsHelmRelease reads the apps helm release of the cluster, name and namespace are defaulted.
func readAppsHelmRelease(ctx kube.Context) (appsHelmRelease, error) {
	var appsHr appsHelmRelease
	hrPath := filepath.Join(ctx.ClusterPath, clusterAppsHrFile)
	hrContent, err := os.ReadFile(hrPath)
	if err != nil {
		return appsHr, errs.WithEF(err, data.WithField("path", hrPath), "Failed to read the apps helm release of the cluster")
	}
	if err := yaml.Unmarshal(hrContent, &appsHr); err != nil {
		return appsHr, errs.WithEF(err, data.WithField("path", hrPath), "Failed to parse the apps helm release of the cluster")
	}
	if appsHr.Metadata.Name == "" {
		appsHr.Metadata.Name = appsChartName
	}
	if appsHr.Metadata.Namespace == "" {
		appsHr.Metadata.Namespace = defaultAppsNamespace
	}
	return appsHr, nil
}

// renderGroupApps renders apps with the values of the cluster, restricted to the group, then renders the app chart of each app of the group.
// It also returns the git repositories of the apps chart, with their namespaces, adopted by the apps helm release: flux needs them to fetch the charts.
func renderGroupApps(ctx kube.Context, opts bootstrapRemoteOptions) ([]renderedApp, []map[string]any, error) {
	if bcl.BCL.EmbeddedPath == "" {
		return nil, nil, errs.With("The charts are not embedded in this build")
	}
	chartsPath := filepath.Join(bcl.BCL.EmbeddedPath, bclChartsFolder)

	appsHr, err := readAppsHelmRelease(ctx)
	if err != nil {
		return nil, nil, err
	}

	appsChart, err := bclhelm.LoadChartWithLocalDependencies(filepath.Join(chartsPath, appsChartName))
	if err != nil {
		return nil, nil, err
	}

	values := appsHr.Spec.Values
	if values == nil {
		values = map[string]any{}
	}

	// the apps of the group, from the default values of the chart overridden by the values of the cluster
	groupApps := appsOfGroup(mergeValues(deepCopyMap(appsChart.Values), deepCopyMap(values)), opts.group)
	if len(groupApps) == 0 {
		return nil, nil, errs.WithF(data.WithField("group", opts.group), "No app belongs to the group")
	}

	// only the group is enabled, every other group the cluster may enable is disabled
	groups := map[string]any{}
	if existing, ok := values["appsGroups"].(map[string]any); ok {
		for name := range existing {
			groups[name] = map[string]any{"enabled": false}
		}
	}
	groups[opts.group] = map[string]any{"enabled": true}
	values["appsGroups"] = groups

	manifest, err := bclhelm.RenderChart(appsChart, values, appsHr.Metadata.Name, appsHr.Metadata.Namespace, opts.kubeVersion)
	if err != nil {
		return nil, nil, err
	}
	appsDocs, err := splitManifest(manifest)
	if err != nil {
		return nil, nil, err
	}

	var apps []renderedApp
	for _, name := range groupApps {
		hrName := appChartPrefix + name
		hr := findDoc(appsDocs, "HelmRelease", hrName)
		if hr == nil {
			logs.WithField("app", name).Info("App is disabled by the cluster values, skipping")
			continue
		}

		// the app lives in its own namespace, flux installs the release there under the name of the helm release
		hrNamespace, _ := nestedValue(hr, "metadata", "namespace").(string)
		releaseName := hrName
		if override, _ := nestedValue(hr, "spec", "releaseName").(string); override != "" {
			releaseName = override
		}
		releaseNamespace := hrNamespace
		if targetNamespace, _ := nestedValue(hr, "spec", "targetNamespace").(string); targetNamespace != "" {
			releaseNamespace = targetNamespace
		}

		appValues, err := helmReleaseValues(hr, appsDocs)
		if err != nil {
			return nil, nil, errs.WithEF(err, data.WithField("app", name), "Failed to compute the values of the app")
		}

		// the chart of the app is the chart of the helm release: ./kube/charts/<name>
		chartPath, _ := nestedValue(hr, "spec", "chart", "spec", "chart").(string)
		appChart, err := bclhelm.LoadChartWithLocalDependencies(filepath.Join(chartsPath, filepath.Base(chartPath)))
		if err != nil {
			return nil, nil, err
		}
		appManifest, err := bclhelm.RenderChart(appChart, appValues, releaseName, releaseNamespace, opts.kubeVersion)
		if err != nil {
			return nil, nil, err
		}
		docs, err := splitManifest(appManifest)
		if err != nil {
			return nil, nil, err
		}

		// the namespace of the app is created by apps, the system namespaces are not
		if ns := findNamespace(appsDocs, releaseNamespace); ns != nil {
			docs = append([]map[string]any{ns}, docs...)
		}
		apps = append(apps, renderedApp{name: name, docs: docs})
	}

	return apps, gitRepositoryDocs(appsDocs, appsHr.Metadata.Name, appsHr.Metadata.Namespace), nil
}

// gitRepositoryDocs returns the GitRepository resources of the docs, and the Namespace resources they are in.
// They are marked as owned by the helm release, so it adopts them when flux installs the chart that renders them.
func gitRepositoryDocs(docs []map[string]any, releaseName string, releaseNamespace string) []map[string]any {
	var repositories []map[string]any
	namespaces := map[string]bool{}
	for _, doc := range docs {
		if doc["kind"] != "GitRepository" {
			continue
		}
		repositories = append(repositories, doc)
		if namespace, _ := nestedValue(doc, "metadata", "namespace").(string); namespace != "" {
			namespaces[namespace] = true
		}
	}

	var result []map[string]any
	for _, doc := range docs {
		if name, _ := nestedValue(doc, "metadata", "name").(string); doc["kind"] == "Namespace" && namespaces[name] {
			result = append(result, doc)
		}
	}
	result = append(result, repositories...)

	for _, doc := range result {
		metadata, _ := doc["metadata"].(map[string]any)
		if metadata == nil {
			metadata = map[string]any{}
			doc["metadata"] = metadata
		}
		labels, _ := metadata["labels"].(map[string]any)
		if labels == nil {
			labels = map[string]any{}
			metadata["labels"] = labels
		}
		labels["app.kubernetes.io/managed-by"] = "Helm"
		annotations, _ := metadata["annotations"].(map[string]any)
		if annotations == nil {
			annotations = map[string]any{}
			metadata["annotations"] = annotations
		}
		annotations["meta.helm.sh/release-name"] = releaseName
		annotations["meta.helm.sh/release-namespace"] = releaseNamespace
	}
	return result
}

// appsOfGroup returns the sorted names of the apps declaring the group in `apps.<name>.groups.<group>: true` of the values.
func appsOfGroup(values map[string]any, group string) []string {
	var names []string
	apps, _ := values["apps"].(map[string]any)
	for name, app := range apps {
		appMap, _ := app.(map[string]any)
		groups, _ := appMap["groups"].(map[string]any)
		if member, _ := groups[group].(bool); member {
			names = append(names, name)
		}
	}
	sort.Strings(names)
	return names
}

// findNamespace returns the Namespace resource named name, nil when there is none.
func findNamespace(docs []map[string]any, name string) map[string]any {
	return findDoc(docs, "Namespace", name)
}

// deepCopyMap copies the maps and the slices of values, so merging into the copy does not alter the original.
func deepCopyMap(values map[string]any) map[string]any {
	result := make(map[string]any, len(values))
	for k, v := range values {
		result[k] = deepCopyValue(v)
	}
	return result
}

func deepCopyValue(value any) any {
	switch v := value.(type) {
	case map[string]any:
		return deepCopyMap(v)
	case []any:
		result := make([]any, len(v))
		for i, item := range v {
			result[i] = deepCopyValue(item)
		}
		return result
	default:
		return v
	}
}

// helmReleaseValues computes the values flux gives to the chart: the valuesFrom config maps in order, then the inline values.
func helmReleaseValues(hr map[string]any, docs []map[string]any) (map[string]any, error) {
	result := map[string]any{}
	hrNamespace, _ := nestedValue(hr, "metadata", "namespace").(string)

	valuesFrom, _ := nestedValue(hr, "spec", "valuesFrom").([]any)
	for _, from := range valuesFrom {
		fromMap, _ := from.(map[string]any)
		kind, _ := fromMap["kind"].(string)
		name, _ := fromMap["name"].(string)
		if kind != "ConfigMap" {
			return nil, errs.WithF(data.WithField("kind", kind).WithField("name", name), "Only ConfigMap valuesFrom are supported")
		}
		key, _ := fromMap["valuesKey"].(string)
		if key == "" {
			key = "values.yaml"
		}

		configMap := findDocInNamespace(docs, kind, name, hrNamespace)
		if configMap == nil {
			return nil, errs.WithF(data.WithField("name", name).WithField("namespace", hrNamespace), "ConfigMap of valuesFrom not found in the rendered apps")
		}
		content, _ := nestedValue(configMap, "data", key).(string)
		var fromValues map[string]any
		if err := yaml.Unmarshal([]byte(content), &fromValues); err != nil {
			return nil, errs.WithEF(err, data.WithField("name", name).WithField("key", key), "Failed to parse the values of the ConfigMap")
		}
		result = mergeValues(result, fromValues)
	}

	inline, _ := nestedValue(hr, "spec", "values").(map[string]any)
	return mergeValues(result, inline), nil
}

// mergeValues deeply merges override on top of base.
func mergeValues(base map[string]any, override map[string]any) map[string]any {
	for k, v := range override {
		overrideMap, overrideIsMap := v.(map[string]any)
		baseMap, baseIsMap := base[k].(map[string]any)
		if overrideIsMap && baseIsMap {
			base[k] = mergeValues(baseMap, overrideMap)
		} else {
			base[k] = v
		}
	}
	return base
}

func splitManifest(manifest string) ([]map[string]any, error) {
	var docs []map[string]any
	decoder := yaml.NewDecoder(strings.NewReader(manifest))
	for {
		var doc map[string]any
		if err := decoder.Decode(&doc); err != nil {
			if errors.Is(err, io.EOF) {
				return docs, nil
			}
			return nil, errs.WithE(err, "Failed to parse the rendered manifest")
		}
		if len(doc) > 0 {
			docs = append(docs, doc)
		}
	}
}

func nestedValue(doc map[string]any, keys ...string) any {
	var current any = doc
	for _, key := range keys {
		m, ok := current.(map[string]any)
		if !ok {
			return nil
		}
		current = m[key]
	}
	return current
}

func findDoc(docs []map[string]any, kind string, name string) map[string]any {
	for _, doc := range docs {
		if doc["kind"] == kind && nestedValue(doc, "metadata", "name") == name {
			return doc
		}
	}
	return nil
}

// findDocInNamespace is findDoc for a namespaced resource, the same name exists in several namespaces.
func findDocInNamespace(docs []map[string]any, kind string, name string, namespace string) map[string]any {
	for _, doc := range docs {
		if doc["kind"] == kind && nestedValue(doc, "metadata", "name") == name && nestedValue(doc, "metadata", "namespace") == namespace {
			return doc
		}
	}
	return nil
}

// applyRenderedApps applies the namespaces, then the kustomizations coming from git repositories (ex: the Gateway API CRDs, which cilium needs
// when it starts), then the helm releases coming from helm repositories, then the flux kustomizations coming from oci repositories.
// Other resources, like helm releases built from the bcl git repository, are left to flux.
func applyRenderedApps(ctx kube.Context, apps []renderedApp, adoptResources bool) error {
	tmpDir, err := os.MkdirTemp("", "bcl-bootstrap-remote-")
	if err != nil {
		return errs.WithE(err, "Failed to create temp directory")
	}
	defer func() {
		if err := os.RemoveAll(tmpDir); err != nil {
			logs.WithField("dir", tmpDir).WithField("error", err.Error()).Info("Failed to remove temp dir")
		}
	}()

	type fluxResource struct {
		folder string
		ref    flux.NamespacedObjectKindReference
	}
	type gitKustomization struct {
		app        string
		kustomize  map[string]any
		repository map[string]any
	}
	var namespaces []map[string]any
	var gitKustomizations []gitKustomization
	var helmReleases []fluxResource
	var kustomizations []fluxResource

	for _, app := range apps {
		appDir := filepath.Join(tmpDir, app.name)
		if err := os.MkdirAll(appDir, 0o700); err != nil {
			return errs.WithEF(err, data.WithField("path", appDir), "Failed to create app temp directory")
		}

		for i, doc := range app.docs {
			kind, _ := doc["kind"].(string)
			name, _ := nestedValue(doc, "metadata", "name").(string)
			namespace, _ := nestedValue(doc, "metadata", "namespace").(string)
			ref := flux.NamespacedObjectKindReference{Kind: kind, Name: name, Namespace: namespace}
			sourceKind, _ := nestedValue(doc, "spec", "sourceRef", "kind").(string)
			chartSourceKind, _ := nestedValue(doc, "spec", "chart", "spec", "sourceRef", "kind").(string)

			switch {
			case kind == "Namespace":
				namespaces = append(namespaces, doc)
				continue
			case kind == "Kustomization" && sourceKind == "GitRepository":
				sourceName, _ := nestedValue(doc, "spec", "sourceRef", "name").(string)
				sourceNamespace, _ := nestedValue(doc, "spec", "sourceRef", "namespace").(string)
				if sourceNamespace == "" {
					sourceNamespace = namespace
				}
				repository := findDocInNamespace(app.docs, "GitRepository", sourceName, sourceNamespace)
				if repository == nil {
					return errs.WithF(data.WithField("app", app.name).WithField("kustomization", name).WithField("repository", sourceName), "GitRepository of the kustomization not found in the app resources")
				}
				gitKustomizations = append(gitKustomizations, gitKustomization{app: app.name, kustomize: doc, repository: repository})
				continue
			case kind == "HelmRepository" || kind == "OCIRepository":
			case kind == "HelmRelease" && chartSourceKind == "HelmRepository":
				helmReleases = append(helmReleases, fluxResource{folder: appDir, ref: ref})
			case kind == "Kustomization" && sourceKind == "OCIRepository":
				kustomizations = append(kustomizations, fluxResource{folder: appDir, ref: ref})
			default:
				logs.WithField("app", app.name).WithField("kind", kind).WithField("name", name).Debug("Left to flux")
				continue
			}

			content, err := yaml.Marshal(doc)
			if err != nil {
				return errs.WithEF(err, data.WithField("app", app.name).WithField("kind", kind).WithField("name", name), "Failed to marshal resource")
			}
			file := filepath.Join(appDir, fmt.Sprintf("%03d-%s-%s.yaml", i, strings.ToLower(kind), name))
			if err := os.WriteFile(file, content, 0o600); err != nil {
				return errs.WithEF(err, data.WithField("path", file), "Failed to write resource")
			}
		}
	}

	if err := applyNamespaces(ctx, namespaces); err != nil {
		return errs.WithE(err, "Failed to apply namespaces")
	}

	// before the helm releases: cilium detects the Gateway API CRDs only when its operator starts
	for _, ks := range gitKustomizations {
		if err := applyGitKustomization(ctx, ks.kustomize, ks.repository); err != nil {
			return errs.WithEF(err, data.WithField("app", ks.app).WithField("name", nestedValue(ks.kustomize, "metadata", "name")), "Failed to apply kustomization")
		}
	}

	for _, hr := range helmReleases {
		if err := applyFluxHelmReleaseWithHelm(ctx, hr.folder, hr.ref, nil, adoptResources); err != nil {
			return errs.WithEF(err, data.WithField("name", hr.ref.Name), "Failed to apply helm release")
		}
	}

	for _, ks := range kustomizations {
		if err := applyFluxKustomizationWithKustomize(ctx, ks.folder, ks.ref); err != nil {
			return errs.WithEF(err, data.WithField("name", ks.ref.Name), "Failed to apply kustomization")
		}
	}

	return nil
}

// applyGitKustomization applies the path of a git repository like a flux Kustomization would, with a remote kustomize, then waits for the CRDs it
// created. The server side apply is required by the size of the CRDs, flux takes the fields over afterward.
func applyGitKustomization(ctx kube.Context, ks map[string]any, repository map[string]any) error {
	url, _ := nestedValue(repository, "spec", "url").(string)
	if url == "" {
		return errs.With("The GitRepository has no url")
	}
	ref, _ := nestedValue(repository, "spec", "ref", "tag").(string)
	if ref == "" {
		ref, _ = nestedValue(repository, "spec", "ref", "branch").(string)
	}

	target := strings.TrimSuffix(url, "/")
	if path := strings.Trim(strings.TrimPrefix(fmt.Sprint(nestedValueOr(ks, "", "spec", "path")), "./"), "/"); path != "" && path != "." {
		target += "//" + path
	}
	if ref != "" {
		target += "?ref=" + ref
	}

	logs.WithField("target", target).Info("Applying kustomization from git repository")
	apply := exec.Command("kubectl", "apply", "--server-side", "--force-conflicts", "-o", "name", "-k", target)
	apply.Env = append(os.Environ(), fmt.Sprintf("KUBECONFIG=%s", ctx.KubeConfig))
	var stderr bytes.Buffer
	apply.Stderr = &stderr
	output, err := apply.Output()
	if err != nil {
		return errs.WithEF(err, data.WithField("output", string(output)+stderr.String()).WithField("target", target), "Failed to apply the kustomization")
	}

	var crds []string
	for _, line := range strings.Split(string(output), "\n") {
		if strings.HasPrefix(line, "customresourcedefinition") {
			crds = append(crds, strings.TrimSpace(line))
		}
	}
	if len(crds) == 0 {
		return nil
	}

	logs.WithField("count", len(crds)).Info("Waiting for the CRDs to be established")
	wait := exec.Command("kubectl", append([]string{"wait", "--for=condition=Established", "--timeout=120s"}, crds...)...)
	wait.Env = append(os.Environ(), fmt.Sprintf("KUBECONFIG=%s", ctx.KubeConfig))
	if waitOutput, err := wait.CombinedOutput(); err != nil {
		return errs.WithEF(err, data.WithField("output", string(waitOutput)), "CRDs are not established")
	}
	return nil
}

func nestedValueOr(doc map[string]any, fallback any, keys ...string) any {
	if value := nestedValue(doc, keys...); value != nil {
		return value
	}
	return fallback
}

func applyNamespaces(ctx kube.Context, namespaces []map[string]any) error {
	return applyDocs(ctx, namespaces, "namespaces")
}

// applyDocs applies the resources with kubectl, what is only used in logs and errors.
func applyDocs(ctx kube.Context, docs []map[string]any, what string) error {
	if len(docs) == 0 {
		return nil
	}

	var content bytes.Buffer
	for _, doc := range docs {
		out, err := yaml.Marshal(doc)
		if err != nil {
			return errs.WithE(err, "Failed to marshal "+what)
		}
		content.WriteString("---\n")
		content.Write(out)
	}

	logs.Info("Applying " + what)
	cmd := exec.Command("kubectl", "apply", "-f", "-")
	cmd.Env = append(os.Environ(), fmt.Sprintf("KUBECONFIG=%s", ctx.KubeConfig))
	cmd.Stdin = &content
	output, err := cmd.CombinedOutput()
	if err != nil {
		return errs.WithEF(err, data.WithField("output", string(output)), "Failed to apply "+what)
	}
	return nil
}
