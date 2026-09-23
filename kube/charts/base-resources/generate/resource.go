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

	helmTemplateRenderArgs map[string]string
}

type mutations struct {
	ExtractContent  *mutation.ExtractContent  `yaml:"extractContent"`
	ArraysToMaps    *mutation.ArraysToMaps    `yaml:"arraysToMaps"`
	StringifyFields *mutation.StringifyFields `yaml:"stringifyFields"`
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
