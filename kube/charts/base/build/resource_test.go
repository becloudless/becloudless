package build

import (
	"os"
	"path/filepath"
	"reflect"
	"testing"

	"github.com/becloudless/becloudless/kube/charts/base/templates/resources/mutations/arraysToMaps"
	"github.com/becloudless/becloudless/kube/charts/base/templates/resources/mutations/itemFields"
	"github.com/becloudless/becloudless/kube/charts/base/templates/resources/mutations/listShorthands"
	"github.com/becloudless/becloudless/kube/charts/base/templates/resources/mutations/stringifyFields"
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
	want := &arraysToMaps.ArraysToMaps{
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
	wantFields := &stringifyFields.StringifyFields{Fields: []string{"data"}}
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

func TestParseCRDs_ParsesClusterScoped(t *testing.T) {
	path := writeResourcesYAML(t, `resources:
  - name: namespaces
    clusterScoped: true
    sourceOpenAPI:
      url: https://example.invalid/namespace.json
      component: io.k8s.api.core.v1.Namespace
    apiVersion: v1
    kind: Namespace
  - name: configMaps
    sourceOpenAPI:
      url: https://example.invalid/configmap.json
      component: io.k8s.api.core.v1.ConfigMap
    apiVersion: v1
    kind: ConfigMap
`)

	file, err := newResourcesFile(path)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if !file.Resources[0].ClusterScoped {
		t.Errorf("namespaces.ClusterScoped = false, want true")
	}
	if file.Resources[1].ClusterScoped {
		t.Errorf("configMaps.ClusterScoped = true, want false")
	}
}

func TestParseCRDs_ParsesItemFieldsWithAnchors(t *testing.T) {
	path := writeResourcesYAML(t, `resources:
  - name: policies
    sourceCRD:
      url: https://example.invalid/policies.yaml
      crdVersion: v2
    mutations: &policyMutations
      itemFields:
        ingress.toPorts.ports: &port {keyField: port, defaults: {protocol: TCP}}
        egress.toPorts.ports: *port
  - name: clusterPolicies
    sourceCRD:
      url: https://example.invalid/clusterpolicies.yaml
      crdVersion: v2
    mutations: *policyMutations
`)

	file, err := newResourcesFile(path)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	want := itemFields.ItemFields{
		"ingress.toPorts.ports": {KeyField: "port", Defaults: map[string]string{"protocol": "TCP"}},
		"egress.toPorts.ports":  {KeyField: "port", Defaults: map[string]string{"protocol": "TCP"}},
	}
	for _, e := range file.Resources {
		if !reflect.DeepEqual(e.Mutations.ItemFields, want) {
			t.Errorf("%s: Mutations.ItemFields = %#v, want %#v", e.Name, e.Mutations.ItemFields, want)
		}
	}
}

func TestParseCRDs_ParsesListShorthands(t *testing.T) {
	path := writeResourcesYAML(t, `resources:
  - name: policies
    sourceCRD:
      url: https://example.invalid/policies.yaml
      crdVersion: v2
    mutations:
      listShorthands:
        ingress.toPorts: &toPorts {key: main, field: ports}
        egress.toPorts: *toPorts
`)

	file, err := newResourcesFile(path)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	want := listShorthands.ListShorthands{
		"ingress.toPorts": {Key: "main", Field: "ports"},
		"egress.toPorts":  {Key: "main", Field: "ports"},
	}
	if got := file.Resources[0].Mutations.ListShorthands; !reflect.DeepEqual(got, want) {
		t.Errorf("Mutations.ListShorthands = %#v, want %#v", got, want)
	}
}
