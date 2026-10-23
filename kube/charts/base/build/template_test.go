package build

import (
"os"
"path/filepath"
"strings"
"testing"
)

func TestGenerateTemplate_PassesClusterScopedOnlyWhenSet(t *testing.T) {
	dir := t.TempDir()
	entries := []resource{
		{Name: "namespaces", APIVersion: "v1", Kind: "Namespace", ClusterScoped: true},
		{Name: "configMaps", APIVersion: "v1", Kind: "ConfigMap"},
	}

	if err := generateTemplate(dir, entries); err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	out, err := os.ReadFile(filepath.Join(dir, "templates", "resources", "_renderResources.tpl"))
	if err != nil {
		t.Fatalf("read generated template: %v", err)
	}

	for _, line := range strings.Split(string(out), "\n") {
		switch {
		case strings.Contains(line, `"name" "namespaces"`):
			if !strings.Contains(line, `"clusterScoped" true`) {
				t.Errorf("namespaces call has no clusterScoped arg: %s", line)
			}
		case strings.Contains(line, `"name" "configMaps"`):
			if strings.Contains(line, "clusterScoped") {
				t.Errorf("configMaps call has a clusterScoped arg: %s", line)
			}
		}
	}
}
