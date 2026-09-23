package generate

import (
	"fmt"
	"os"

	"resourceschart/generate/mutation"

	"gopkg.in/yaml.v3"
)

type resourcesFile struct {
	Resources []resource `yaml:"resources"`
}

type resource struct {
	Name       string    `yaml:"name"`
	URL        string    `yaml:"url"`
	APIVersion string    `yaml:"apiVersion"`
	Kind       string    `yaml:"kind"`
	CRDVersion string    `yaml:"crdVersion"` // optional; set to fetch the schema from a CRD manifest (YAML) instead of Kubernetes' own OpenAPI v3 spec
	Component  string    `yaml:"component"`  // optional; set to the fully-qualified component name (e.g. io.k8s.api.core.v1.ConfigMap) to fetch from a Kubernetes OpenAPI v3 spec document at URL (see fetchOpenAPIV3Schema)
	Mutations  mutations `yaml:"mutations"`

	// templateArgs holds the named, render-time template arguments the
	// mutation pipeline contributed for this resource kind (see
	// mutation.Result.TemplateArgs), e.g. "required", "contentIsSpec",
	// "stringifyFields". Populated after running the pipeline (see
	// fetchAndMutateSchema) and consumed by generateTemplate to build
	// each kind's "base-resources.renderResourceKind" call, without
	// generateTemplate needing to know about specific mutation names.
	templateArgs map[string]string
}

// mutations declares per-resource-kind configuration for the mutation
// pipeline (see mutation.Pipeline), as a nested "mutations" block in
// resources.yaml:
//
//	mutations:
//	  arraysToMaps:
//	    ignore:
//	      - template.spec.containers.command
//	  stringifyFields:
//	    fields:
//	      - data
//	  contentIsOutOfSpec: true
//
// A zero value (nil pointer, or false) means the corresponding mutation
// runs with no special configuration for this kind. ArraysToMaps and
// StringifyFields are the mutation package's own mutation types (see
// mutation.ArraysToMaps, mutation.StringifyFields), decoded directly from
// YAML and passed as-is to mutation.Pipeline - no separate config type.
type mutations struct {
	ArraysToMaps    *mutation.ArraysToMaps    `yaml:"arraysToMaps"`
	StringifyFields *mutation.StringifyFields `yaml:"stringifyFields"`

	// ContentIsOutOfSpec marks a kind whose content is taken from the
	// schema's top-level properties (minus
	// apiVersion/kind/metadata/status) instead of its "spec" property, for
	// core kinds that have no "spec" of their own (e.g. ConfigMap, Secret,
	// ServiceAccount); consumed by mutation.ExtractContent. It also
	// controls whether the resulting manifest wraps the resource's values
	// in `spec:` at render time (see generateTemplate).
	ContentIsOutOfSpec bool `yaml:"contentIsOutOfSpec"`
}

func newResourcesFile(path string) (resourcesFile, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return resourcesFile{}, err
	}

	var file resourcesFile
	if err := yaml.Unmarshal(data, &file); err != nil {
		return resourcesFile{}, fmt.Errorf("parse %s: %w", path, err)
	}

	for i := range file.Resources {
		if file.Resources[i].Name == "" {
			return resourcesFile{}, fmt.Errorf("%s: resource is missing a name", path)
		}
	}
	return file, nil
}
