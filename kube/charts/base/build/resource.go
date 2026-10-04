package build

import (
	"fmt"
	"os"

	"github.com/becloudless/becloudless/kube/charts/base/templates/resources/mutations/arraysToMaps"
	"github.com/becloudless/becloudless/kube/charts/base/templates/resources/mutations/content"
	"github.com/becloudless/becloudless/kube/charts/base/templates/resources/mutations/stringifyFields"

	"gopkg.in/yaml.v3"
)

type resourcesFile struct {
	Resources []resource `yaml:"resources"`
}

type resource struct {
	Name          string            `yaml:"name"`
	APIVersion    string            `yaml:"apiVersion"`    // required for sourceOpenAPI; self-deduced from the CRD manifest for sourceCRD, no need to set it
	Kind          string            `yaml:"kind"`          // required for sourceOpenAPI; self-deduced from the CRD manifest for sourceCRD, no need to set it
	SourceOpenAPI *SourceOpenAPI    `yaml:"sourceOpenAPI"` // set to fetch the schema from a Kubernetes OpenAPI v3 spec document
	SourceCRD     *SourceCRD        `yaml:"sourceCRD"`     // set to fetch the schema from a CRD manifest (YAML)
	Mutations     resourceMutations `yaml:"mutations"`

	helmTemplateRenderArgs map[string]string
}

type SourceOpenAPI struct {
	URL       string `yaml:"url"`
	Component string `yaml:"component"` // fully-qualified component name, e.g. io.k8s.api.core.v1.ConfigMap (see fetchOpenAPIV3Schema)
}

type SourceCRD struct {
	URL        string `yaml:"url"`
	CRDVersion string `yaml:"crdVersion"`
	Kind       string `yaml:"kind"` // optional: only needed to disambiguate when the manifest at URL defines multiple kinds (e.g. a full operator CRD bundle); apiVersion/kind are otherwise self-deduced from the manifest
}

type resourceMutations struct {
	ExtractContent  *content.ExtractContent          `yaml:"extractContent"`
	ArraysToMaps    *arraysToMaps.ArraysToMaps       `yaml:"arraysToMaps"`
	StringifyFields *stringifyFields.StringifyFields `yaml:"stringifyFields"`
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
