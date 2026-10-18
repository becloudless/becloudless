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
	bclChartsFolder     = "assets/kube/charts" // embedded in the binary, extracted under bcl.BCL.EmbeddedPath
	bclAppChartName     = "app-bcl"
	bclAppChartPrefix   = "app-"
	clusterAppBclHrFile = "bcl/app-bcl.hr.yaml"
	bclGitRepoFile      = "bcl/bcl.gitrepo.yaml"
	defaultBclNamespace = "bcl"
	remoteKubeconfig    = "/etc/kubernetes/admin.conf"
	apiServerPort       = "8443"
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
		Long: `Fetch the kubeconfig of the cluster from a server through ssh, then render the app-bcl chart with the values of the cluster
(bcl/app-bcl.hr.yaml) restricted to the apps of the minimal group, render each of these app charts, and apply the resources
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

	apps, err := renderGroupApps(ctx, opts)
	if err != nil {
		return errs.WithE(err, "Failed to render the apps of the group")
	}

	if err := applyRenderedApps(ctx, apps, opts.adoptResources); err != nil {
		return err
	}

	return applyBcl(ctx)
}

// applyBcl hands over to flux: the bcl namespace, the bcl git repository and the app-bcl helm release of the cluster.
func applyBcl(ctx kube.Context) error {
	if err := waitFluxCRDs(ctx); err != nil {
		return errs.WithE(err, "Failed to wait for the flux CRDs")
	}

	if err := applyBclNamespace(ctx); err != nil {
		return errs.WithE(err, "Failed to apply the bcl namespace")
	}

	for _, file := range []string{bclGitRepoFile, clusterAppBclHrFile} {
		logs.WithField("file", file).Info("Applying bcl resources")
		if err := applyResourcesFile(ctx, filepath.Join(ctx.ClusterPath, file)); err != nil {
			return errs.WithEF(err, data.WithField("file", file), "Failed to apply bcl resources")
		}
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

// renderGroupApps renders app-bcl with the values of the cluster, restricted to the group, then renders the app chart of each app of the group.
func renderGroupApps(ctx kube.Context, opts bootstrapRemoteOptions) ([]renderedApp, error) {
	if bcl.BCL.EmbeddedPath == "" {
		return nil, errs.With("The charts are not embedded in this build")
	}
	chartsPath := filepath.Join(bcl.BCL.EmbeddedPath, bclChartsFolder)

	hrPath := filepath.Join(ctx.ClusterPath, clusterAppBclHrFile)
	hrContent, err := os.ReadFile(hrPath)
	if err != nil {
		return nil, errs.WithEF(err, data.WithField("path", hrPath), "Failed to read the app-bcl helm release of the cluster")
	}
	var appBclHr struct {
		Metadata flux.Metadata `yaml:"metadata"`
		Spec     struct {
			Values map[string]any `yaml:"values"`
		} `yaml:"spec"`
	}
	if err := yaml.Unmarshal(hrContent, &appBclHr); err != nil {
		return nil, errs.WithEF(err, data.WithField("path", hrPath), "Failed to parse the app-bcl helm release of the cluster")
	}
	if appBclHr.Metadata.Name == "" {
		appBclHr.Metadata.Name = bclAppChartName
	}
	if appBclHr.Metadata.Namespace == "" {
		appBclHr.Metadata.Namespace = defaultBclNamespace
	}

	appBclChart, err := bclhelm.LoadChartWithLocalDependencies(filepath.Join(chartsPath, bclAppChartName))
	if err != nil {
		return nil, err
	}

	groupApps := appsOfGroup(appBclChart.Values, opts.group)
	if len(groupApps) == 0 {
		return nil, errs.WithF(data.WithField("group", opts.group), "No app belongs to the group")
	}

	// only the group is enabled, every other group the cluster may enable is disabled
	values := appBclHr.Spec.Values
	if values == nil {
		values = map[string]any{}
	}
	groups := map[string]any{}
	if existing, ok := values["appsGroups"].(map[string]any); ok {
		for name := range existing {
			groups[name] = map[string]any{"enabled": false}
		}
	}
	groups[opts.group] = map[string]any{"enabled": true}
	values["appsGroups"] = groups

	manifest, err := bclhelm.RenderChart(appBclChart, values, appBclHr.Metadata.Name, appBclHr.Metadata.Namespace, opts.kubeVersion)
	if err != nil {
		return nil, err
	}
	appBclDocs, err := splitManifest(manifest)
	if err != nil {
		return nil, err
	}

	var apps []renderedApp
	for _, name := range groupApps {
		hrName := bclAppChartPrefix + name
		hr := findDoc(appBclDocs, "HelmRelease", hrName)
		if hr == nil {
			logs.WithField("app", name).Info("App is disabled by the cluster values, skipping")
			continue
		}

		hrNamespace, _ := nestedValue(hr, "metadata", "namespace").(string)
		if hrNamespace == "" {
			hrNamespace = appBclHr.Metadata.Namespace
		}

		appValues, err := helmReleaseValues(hr, appBclDocs)
		if err != nil {
			return nil, errs.WithEF(err, data.WithField("app", name), "Failed to compute the values of the app")
		}

		appChart, err := bclhelm.LoadChartWithLocalDependencies(filepath.Join(chartsPath, hrName))
		if err != nil {
			return nil, err
		}
		appManifest, err := bclhelm.RenderChart(appChart, appValues, hrName, hrNamespace, opts.kubeVersion)
		if err != nil {
			return nil, err
		}
		docs, err := splitManifest(appManifest)
		if err != nil {
			return nil, err
		}
		apps = append(apps, renderedApp{name: name, docs: docs})
	}

	return apps, nil
}

// appsOfGroup returns the sorted names of the apps declaring the group in `apps.<name>.groups` of the chart values.
func appsOfGroup(chartValues map[string]any, group string) []string {
	var names []string
	apps, _ := chartValues["apps"].(map[string]any)
	for name, app := range apps {
		appMap, _ := app.(map[string]any)
		groups, _ := appMap["groups"].([]any)
		for _, g := range groups {
			if g == group {
				names = append(names, name)
				break
			}
		}
	}
	sort.Strings(names)
	return names
}

// helmReleaseValues computes the values flux gives to the chart: the valuesFrom config maps in order, then the inline values.
func helmReleaseValues(hr map[string]any, docs []map[string]any) (map[string]any, error) {
	result := map[string]any{}

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

		configMap := findDoc(docs, kind, name)
		if configMap == nil {
			return nil, errs.WithF(data.WithField("name", name), "ConfigMap of valuesFrom not found in the rendered app-bcl")
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

// applyRenderedApps applies the namespaces, then the helm releases coming from helm repositories, then the flux kustomizations coming from oci repositories.
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
	var namespaces []map[string]any
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

func applyNamespaces(ctx kube.Context, namespaces []map[string]any) error {
	if len(namespaces) == 0 {
		return nil
	}

	var content bytes.Buffer
	for _, ns := range namespaces {
		out, err := yaml.Marshal(ns)
		if err != nil {
			return errs.WithE(err, "Failed to marshal namespace")
		}
		content.WriteString("---\n")
		content.Write(out)
	}

	logs.Info("Applying namespaces")
	cmd := exec.Command("kubectl", "apply", "-f", "-")
	cmd.Env = append(os.Environ(), fmt.Sprintf("KUBECONFIG=%s", ctx.KubeConfig))
	cmd.Stdin = &content
	output, err := cmd.CombinedOutput()
	if err != nil {
		return errs.WithEF(err, data.WithField("output", string(output)), "Failed to apply namespaces")
	}
	return nil
}
