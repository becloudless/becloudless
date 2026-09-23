package generate

import (
	"os"
	"path/filepath"
	"reflect"
	"testing"
)

func writeResourcesYAML(t *testing.T, content string) string {
	t.Helper()
	path := filepath.Join(t.TempDir(), "resources.yaml")
	if err := os.WriteFile(path, []byte(content), 0o644); err != nil {
		t.Fatalf("write %s: %v", path, err)
	}
	return path
}

func TestParseCRDs_ParsesMutationConfig(t *testing.T) {
	path := writeResourcesYAML(t, `resources:
  - name: deployments
    url: https://example.invalid/deployment.json
    apiVersion: apps/v1
    kind: Deployment
    mutations:
      arraysToMaps:
        ignore:
          - template.spec.containers.command
          - template.spec.containers.args
`)

	file, err := newResourcesFile(path)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	entries := file.Resources
	if len(entries) != 1 {
		t.Fatalf("len(entries) = %d, want 1", len(entries))
	}

	got := entries[0].mutationConfig
	want := map[string]map[string][]string{
		"arraysToMaps": {
			"ignore": {"template.spec.containers.command", "template.spec.containers.args"},
		},
	}
	if !reflect.DeepEqual(got, want) {
		t.Errorf("mutationConfig = %#v, want %#v", got, want)
	}
}

func TestParseCRDs_ParsesMultipleMutationsAndOptions(t *testing.T) {
	path := writeResourcesYAML(t, `resources:
  - name: deployments
    url: https://example.invalid/deployment.json
    apiVersion: apps/v1
    kind: Deployment
    mutations:
      arraysToMaps:
        ignore:
          - template.spec.containers.command
        other:
          - foo
      anotherMutation:
        option:
          - bar
`)

	file, err := newResourcesFile(path)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	entries := file.Resources
	if len(entries) != 1 {
		t.Fatalf("len(entries) = %d, want 1", len(entries))
	}

	got := entries[0].mutationConfig
	want := map[string]map[string][]string{
		"arraysToMaps": {
			"ignore": {"template.spec.containers.command"},
			"other":  {"foo"},
		},
		"anotherMutation": {
			"option": {"bar"},
		},
	}
	if !reflect.DeepEqual(got, want) {
		t.Errorf("mutationConfig = %#v, want %#v", got, want)
	}
}

func TestParseCRDs_NoMutationConfigLeavesFieldNil(t *testing.T) {
	path := writeResourcesYAML(t, `resources:
  - name: configMaps
    url: https://example.invalid/configmap.json
    apiVersion: v1
    kind: ConfigMap
`)

	file, err := newResourcesFile(path)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	entries := file.Resources
	if len(entries) != 1 {
		t.Fatalf("len(entries) = %d, want 1", len(entries))
	}
	if entries[0].mutationConfig != nil {
		t.Errorf("mutationConfig = %#v, want nil", entries[0].mutationConfig)
	}
}

func TestParseCRDs_EmptyMutationBlockLeavesFieldNil(t *testing.T) {
	path := writeResourcesYAML(t, `resources:
  - name: configMaps
    url: https://example.invalid/configmap.json
    apiVersion: v1
    kind: ConfigMap
    mutations:
  - name: secrets
    url: https://example.invalid/secret.json
    apiVersion: v1
    kind: Secret
`)

	file, err := newResourcesFile(path)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	entries := file.Resources
	if len(entries) != 2 {
		t.Fatalf("len(entries) = %d, want 2", len(entries))
	}
	if entries[0].mutationConfig != nil {
		t.Errorf("configMaps.mutationConfig = %#v, want nil (empty mutations block)", entries[0].mutationConfig)
	}
	// Guards against the empty "mutations:" block on the previous resource
	// leaking state (currentMutation/currentOption) into the next one.
	if entries[1].mutationConfig != nil {
		t.Errorf("secrets.mutationConfig = %#v, want nil", entries[1].mutationConfig)
	}
}

func TestParseCRDs_DoesNotLeakMutationStateBetweenResources(t *testing.T) {
	path := writeResourcesYAML(t, `resources:
  - name: deployments
    url: https://example.invalid/deployment.json
    apiVersion: apps/v1
    kind: Deployment
    mutations:
      arraysToMaps:
        ignore:
          - template.spec.containers.command
  - name: configMaps
    url: https://example.invalid/configmap.json
    apiVersion: v1
    kind: ConfigMap
`)

	file, err := newResourcesFile(path)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	entries := file.Resources
	if len(entries) != 2 {
		t.Fatalf("len(entries) = %d, want 2", len(entries))
	}
	if entries[1].mutationConfig != nil {
		t.Errorf("configMaps.mutationConfig = %#v, want nil (should not inherit deployments' config)", entries[1].mutationConfig)
	}
}
