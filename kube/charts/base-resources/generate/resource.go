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
	Name          string         `yaml:"name"`
	APIVersion    string         `yaml:"apiVersion"`
	Kind          string         `yaml:"kind"`
	SourceOpenAPI *SourceOpenAPI `yaml:"sourceOpenAPI"` // set to fetch the schema from a Kubernetes OpenAPI v3 spec document
	SourceCRD     *SourceCRD     `yaml:"sourceCRD"`     // set to fetch the schema from a CRD manifest (YAML)
	Mutations     mutations      `yaml:"mutations"`

	helmTemplateRenderArgs map[string]string
}

type SourceOpenAPI struct {
	URL       string `yaml:"url"`
	Component string `yaml:"component"` // fully-qualified component name, e.g. io.k8s.api.core.v1.ConfigMap (see fetchOpenAPIV3Schema)
}

type SourceCRD struct {
	URL        string `yaml:"url"`
	CRDVersion string `yaml:"crdVersion"`
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
