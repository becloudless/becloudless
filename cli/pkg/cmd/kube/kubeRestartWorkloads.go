package kube

import (
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"os"
	"os/exec"
	"sort"

	"github.com/becloudless/becloudless/pkg/kube"
	"github.com/n0rad/go-erlog/data"
	"github.com/n0rad/go-erlog/errs"
	"github.com/n0rad/go-erlog/logs"
	"gopkg.in/yaml.v3"
	"helm.sh/helm/v4/pkg/release"
)

var restartableKinds = map[string]bool{"Deployment": true, "DaemonSet": true, "StatefulSet": true}

// releaseManifest returns the manifest of a helm release.
func releaseManifest(rel release.Releaser) (string, error) {
	accessor, err := release.NewAccessor(rel)
	if err != nil {
		return "", errs.WithE(err, "Failed to read the helm release")
	}
	return accessor.Manifest(), nil
}

// configDigest hashes the ConfigMaps and the Secrets of a manifest: what the pods read when they start.
func configDigest(manifest string) (string, error) {
	docs, err := splitManifest(manifest)
	if err != nil {
		return "", err
	}
	var configs []string
	for _, doc := range docs {
		if doc["kind"] != "ConfigMap" && doc["kind"] != "Secret" {
			continue
		}
		content, err := yaml.Marshal(doc)
		if err != nil {
			return "", errs.WithE(err, "Failed to marshal a configuration of the helm release")
		}
		configs = append(configs, string(content))
	}
	sort.Strings(configs)
	hash := sha256.New()
	for _, config := range configs {
		hash.Write([]byte(config))
		hash.Write([]byte{0})
	}
	return hex.EncodeToString(hash.Sum(nil)), nil
}

// restartReleaseWorkloads rolls the pods of an upgraded helm release that do not run with its current configuration: helm only rolls the
// pods when their template changes, not when a ConfigMap or a Secret they read does. The workloads are restarted when the configuration
// changed since the previous revision, or when they are not rolled out (a pod that fails with the previous configuration is not
// fixed by the new one until it is recreated, the kubelet backs it off for minutes). Flux does not do it either, and nothing runs it yet
// while bootstrapping.
func restartReleaseWorkloads(ctx kube.Context, namespace string, previousManifest string, manifest string) error {
	configChanged := false
	if previousManifest != "" {
		before, err := configDigest(previousManifest)
		if err != nil {
			return err
		}
		after, err := configDigest(manifest)
		if err != nil {
			return err
		}
		configChanged = before != after
	}

	docs, err := splitManifest(manifest)
	if err != nil {
		return err
	}
	for _, doc := range docs {
		kind, _ := doc["kind"].(string)
		name, _ := nestedValue(doc, "metadata", "name").(string)
		if !restartableKinds[kind] || name == "" {
			continue
		}
		workloadNamespace, _ := nestedValue(doc, "metadata", "namespace").(string)
		if workloadNamespace == "" {
			workloadNamespace = namespace
		}
		target := fmt.Sprintf("%s/%s", kind, name)
		fields := data.WithField("namespace", workloadNamespace).WithField("workload", target)

		if !configChanged && rolledOut(ctx, workloadNamespace, target) {
			continue
		}

		logs.WithFields(fields).WithField("configChanged", configChanged).Info("Restarting the workload of the helm release")
		cmd := exec.Command("kubectl", "-n", workloadNamespace, "rollout", "restart", target)
		cmd.Env = append(os.Environ(), fmt.Sprintf("KUBECONFIG=%s", ctx.KubeConfig))
		if output, err := cmd.CombinedOutput(); err != nil {
			return errs.WithEF(err, fields.WithField("output", string(output)), "Failed to restart the workload")
		}
	}
	return nil
}

// rolledOut tells whether the pods of the workload are all updated and ready.
func rolledOut(ctx kube.Context, namespace string, target string) bool {
	cmd := exec.Command("kubectl", "-n", namespace, "rollout", "status", target, "--timeout=1s")
	cmd.Env = append(os.Environ(), fmt.Sprintf("KUBECONFIG=%s", ctx.KubeConfig))
	return cmd.Run() == nil
}
