package generate

import (
	"os"
	"path/filepath"
	"reflect"
	"testing"

	"resourceschart/generate/mutation"
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

	got := entries[0].Mutations.ArraysToMaps
	want := &mutation.ArraysToMaps{
		Ignore: []string{"template.spec.containers.command", "template.spec.containers.args"},
	}
	if !reflect.DeepEqual(got, want) {
		t.Errorf("Mutations.ArraysToMaps = %#v, want %#v", got, want)
	}
}

func TestParseCRDs_ParsesContentIsOutOfSpecAndStringifyFields(t *testing.T) {
	path := writeResourcesYAML(t, `resources:
  - name: configMaps
    url: https://example.invalid/configmap.json
    apiVersion: v1
    kind: ConfigMap
    mutations:
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

	if !entries[0].Mutations.ContentIsOutOfSpec {
		t.Errorf("Mutations.ContentIsOutOfSpec = false, want true")
	}
	wantFields := &mutation.StringifyFields{Fields: []string{"data"}}
	if !reflect.DeepEqual(entries[0].Mutations.StringifyFields, wantFields) {
		t.Errorf("Mutations.StringifyFields = %#v, want %#v", entries[0].Mutations.StringifyFields, wantFields)
	}
}

func TestParseCRDs_NoMutationsLeavesFieldsZero(t *testing.T) {
	path := writeResourcesYAML(t, `resources:
  - name: configMaps
    url: https://example.invalid/configmap.json
    apiVersion: v1
    kind: ConfigMap
  - name: secrets
    url: https://example.invalid/secret.json
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
	if entries[0].Mutations.ContentIsOutOfSpec {
		t.Errorf("configMaps.Mutations.ContentIsOutOfSpec = true, want false")
	}
	// Guards against the second resource's mutations config leaking into
	// the first, and vice versa.
	if entries[1].Mutations.ArraysToMaps == nil {
		t.Errorf("secrets.Mutations.ArraysToMaps = nil, want non-nil")
	}
}
