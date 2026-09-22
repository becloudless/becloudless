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

func TestParseCRDs_ParsesTransformerConfig(t *testing.T) {
	path := writeResourcesYAML(t, `resources:
  deployments:
    url: https://example.invalid/deployment.json
    apiVersion: apps/v1
    kind: Deployment
    transformer:
      arraysToMaps:
        ignore:
          - template.spec.containers.command
          - template.spec.containers.args
`)

	entries, err := parseCRDs(path)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(entries) != 1 {
		t.Fatalf("len(entries) = %d, want 1", len(entries))
	}

	got := entries[0].transformerConfig
	want := map[string]map[string][]string{
		"arraysToMaps": {
			"ignore": {"template.spec.containers.command", "template.spec.containers.args"},
		},
	}
	if !reflect.DeepEqual(got, want) {
		t.Errorf("transformerConfig = %#v, want %#v", got, want)
	}
}

func TestParseCRDs_ParsesMultipleTransformersAndOptions(t *testing.T) {
	path := writeResourcesYAML(t, `resources:
  deployments:
    url: https://example.invalid/deployment.json
    apiVersion: apps/v1
    kind: Deployment
    transformer:
      arraysToMaps:
        ignore:
          - template.spec.containers.command
        other:
          - foo
      anotherTransformer:
        option:
          - bar
`)

	entries, err := parseCRDs(path)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(entries) != 1 {
		t.Fatalf("len(entries) = %d, want 1", len(entries))
	}

	got := entries[0].transformerConfig
	want := map[string]map[string][]string{
		"arraysToMaps": {
			"ignore": {"template.spec.containers.command"},
			"other":  {"foo"},
		},
		"anotherTransformer": {
			"option": {"bar"},
		},
	}
	if !reflect.DeepEqual(got, want) {
		t.Errorf("transformerConfig = %#v, want %#v", got, want)
	}
}

func TestParseCRDs_NoTransformerConfigLeavesFieldNil(t *testing.T) {
	path := writeResourcesYAML(t, `resources:
  configMaps:
    url: https://example.invalid/configmap.json
    apiVersion: v1
    kind: ConfigMap
`)

	entries, err := parseCRDs(path)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(entries) != 1 {
		t.Fatalf("len(entries) = %d, want 1", len(entries))
	}
	if entries[0].transformerConfig != nil {
		t.Errorf("transformerConfig = %#v, want nil", entries[0].transformerConfig)
	}
}

func TestParseCRDs_EmptyTransformerBlockLeavesFieldNil(t *testing.T) {
	path := writeResourcesYAML(t, `resources:
  configMaps:
    url: https://example.invalid/configmap.json
    apiVersion: v1
    kind: ConfigMap
    transformer:
  secrets:
    url: https://example.invalid/secret.json
    apiVersion: v1
    kind: Secret
`)

	entries, err := parseCRDs(path)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(entries) != 2 {
		t.Fatalf("len(entries) = %d, want 2", len(entries))
	}
	if entries[0].transformerConfig != nil {
		t.Errorf("configMaps.transformerConfig = %#v, want nil (empty transformer block)", entries[0].transformerConfig)
	}
	// Guards against the empty "transformer:" block on the previous resource
	// leaking state (currentTransformer/currentOption) into the next one.
	if entries[1].transformerConfig != nil {
		t.Errorf("secrets.transformerConfig = %#v, want nil", entries[1].transformerConfig)
	}
}

func TestParseCRDs_DoesNotLeakTransformerStateBetweenResources(t *testing.T) {
	path := writeResourcesYAML(t, `resources:
  deployments:
    url: https://example.invalid/deployment.json
    apiVersion: apps/v1
    kind: Deployment
    transformer:
      arraysToMaps:
        ignore:
          - template.spec.containers.command
  configMaps:
    url: https://example.invalid/configmap.json
    apiVersion: v1
    kind: ConfigMap
`)

	entries, err := parseCRDs(path)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(entries) != 2 {
		t.Fatalf("len(entries) = %d, want 2", len(entries))
	}
	if entries[1].transformerConfig != nil {
		t.Errorf("configMaps.transformerConfig = %#v, want nil (should not inherit deployments' config)", entries[1].transformerConfig)
	}
}
