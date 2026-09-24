package generate

import (
	"os"
	"path/filepath"
	"reflect"
	"testing"

	"resourceschart/generate/mutations"
)

func writeResourcesYAML(t *testing.T, content string) string {
	t.Helper()
	path := filepath.Join(t.TempDir(), "resources.yaml")
	if err := os.WriteFile(path, []byte(content), 0o644); err != nil {
		t.Fatalf("write %s: %v", path, err)
	}
	return path
}

func TestParseCRDs_ParsesArraysToMapsIgnore(t *testing.T) {
	path := writeResourcesYAML(t, `resources:
  - name: deployments
    sourceOpenAPI:
      url: https://example.invalid/deployment.json
      component: io.k8s.api.apps.v1.Deployment
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

	got := entries[0].Mutations.ArraysToMaps
	want := &mutations.ArraysToMaps{
		Ignore: []string{"template.spec.containers.command", "template.spec.containers.args"},
	}
	if !reflect.DeepEqual(got, want) {
		t.Errorf("Mutations.ArraysToMaps = %#v, want %#v", got, want)
	}
}

func TestParseCRDs_ParsesContentIsOutOfSpecAndStringifyFields(t *testing.T) {
	path := writeResourcesYAML(t, `resources:
  - name: configMaps
    sourceOpenAPI:
      url: https://example.invalid/configmap.json
      component: io.k8s.api.core.v1.ConfigMap
    apiVersion: v1
    kind: ConfigMap
    mutations:
      extractContent:
        contentIsOutOfSpec: true
      stringifyFields:
        fields:
          - data
`)

	file, err := newResourcesFile(path)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	entries := file.Resources
	if len(entries) != 1 {
		t.Fatalf("len(entries) = %d, want 1", len(entries))
	}

	if entries[0].Mutations.ExtractContent == nil || !entries[0].Mutations.ExtractContent.ContentIsOutOfSpec {
		t.Errorf("Mutations.ExtractContent.ContentIsOutOfSpec = false, want true")
	}
	wantFields := &mutations.StringifyFields{Fields: []string{"data"}}
	if !reflect.DeepEqual(entries[0].Mutations.StringifyFields, wantFields) {
		t.Errorf("Mutations.StringifyFields = %#v, want %#v", entries[0].Mutations.StringifyFields, wantFields)
	}
}

func TestParseCRDs_NoMutationsLeavesFieldsZero(t *testing.T) {
	path := writeResourcesYAML(t, `resources:
  - name: configMaps
    sourceOpenAPI:
      url: https://example.invalid/configmap.json
      component: io.k8s.api.core.v1.ConfigMap
    apiVersion: v1
    kind: ConfigMap
  - name: secrets
    sourceOpenAPI:
      url: https://example.invalid/secret.json
      component: io.k8s.api.core.v1.Secret
    apiVersion: v1
    kind: Secret
    mutations:
      arraysToMaps:
        ignore:
          - foo
`)

	file, err := newResourcesFile(path)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	entries := file.Resources
	if len(entries) != 2 {
		t.Fatalf("len(entries) = %d, want 2", len(entries))
	}
	if entries[0].Mutations.ArraysToMaps != nil {
		t.Errorf("configMaps.Mutations.ArraysToMaps = %#v, want nil", entries[0].Mutations.ArraysToMaps)
	}
	if entries[0].Mutations.ExtractContent != nil {
		t.Errorf("configMaps.Mutations.ExtractContent = %#v, want nil", entries[0].Mutations.ExtractContent)
	}
	// Guards against the second resource's mutations config leaking into
	// the first, and vice versa.
	if entries[1].Mutations.ArraysToMaps == nil {
		t.Errorf("secrets.Mutations.ArraysToMaps = nil, want non-nil")
	}
}
