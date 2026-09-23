package generate

import (
	"fmt"
	"os"

	"resourceschart/generate/transform"

	"gopkg.in/yaml.v3"
)

// resourcesFile is the top-level shape of resources.yaml:
//
//	resources:
//	  - name: configMaps
//	    url: https://raw.githubusercontent.com/kubernetes/kubernetes/master/api/openapi-spec/v3/api__v1_openapi.json
//	    component: io.k8s.api.core.v1.ConfigMap
//	    apiVersion: v1
//	    kind: ConfigMap
//	    transformer:
//	      contentIsOutOfSpec: true
//
// Resources is a list (rather than a map keyed by name) so that the order
// resource kinds appear in resources.yaml is preserved: Go maps have no
// defined iteration order, and the order kinds appear in is significant -
// it's the order generateTemplate emits each kind's
// "base-resources.renderResourceKind" call in templates/_generated.tpl.
type resourcesFile struct {
	Resources []resourceYAML `yaml:"resources"`
}

// resourceYAML is the YAML shape of one entry under resources.yaml's
// top-level "resources" list. See resource for the field descriptions.
//
// For third-party CRDs whose schema isn't published as part of Kubernetes'
// own OpenAPI v3 spec (e.g. bitnami's SealedSecret), url may instead point
// at the CRD's own YAML manifest, with crdVersion set to the CRD version
// whose spec.versions[].schema.openAPIV3Schema should be extracted and used
// as the kind's schema (see fetchCRDManifestSchema).
type resourceYAML struct {
	Name       string `yaml:"name"`
	URL        string `yaml:"url"`
	APIVersion string `yaml:"apiVersion"`
	Kind       string `yaml:"kind"`
	CRDVersion string `yaml:"crdVersion"`
	Component  string `yaml:"component"`

	// Transformer holds the raw, untyped decode of the "transformer:"
	// block (see resource.transformerConfig for its shape and meaning).
	// Each value is either a bool (a bare presence flag, e.g.
	// "contentIsOutOfSpec: true") or a map[string]any of
	// option -> list-of-strings (e.g. "arraysToMaps: { ignore: [...] }"),
	// normalized into resource.transformerConfig by buildTransformerConfig.
	Transformer map[string]any `yaml:"transformer"`
}

// resource represents one resource kind declared in resources.yaml (see
// resourceYAML for its on-disk shape).
type resource struct {
	name       string
	url        string
	apiVersion string
	kind       string
	crdVersion string // optional; set to fetch the schema from a CRD manifest (YAML) instead of Kubernetes' own OpenAPI v3 spec
	component  string // optional; set to the fully-qualified component name (e.g. io.k8s.api.core.v1.ConfigMap) to fetch from a Kubernetes OpenAPI v3 spec document at url (see fetchOpenAPIV3Schema)

	// templateArgs holds the named, render-time template arguments the
	// transformer pipeline contributed for this resource kind (see
	// transform.Entry.TemplateArgs and transform.Entry.AddTemplateArg),
	// e.g. "required", "contentIsSpec", "stringifyFields". Populated from
	// transform.Entry.TemplateArgs after running the pipeline (see
	// fetchAndTransformSchema) and consumed by generateTemplate to build
	// each kind's "base-resources.renderResourceKind" call, without
	// generateTemplate needing to know about specific transformer names.
	templateArgs []transform.TemplateArg

	// transformerConfig holds optional per-transformer configuration for
	// this resource kind, declared in resources.yaml as a nested
	// "transformer" block:
	//
	//	transformer:
	//	  <transformerName>: <true|false> # boolean flag
	//	  <transformerName>:
	//	    <option>:
	//	      - value1
	//	      - value2
	//
	// Keyed by transformer name, then option name; the value is the list of
	// declared items. A transformer name may also be declared with an
	// explicit boolean value (e.g. "contentIsOutOfSpec: true"), instead of a
	// nested options block, purely to mark its presence for the given kind;
	// its map entry is created (just empty) when the value is exactly
	// "true", and left absent/removed when exactly "false" (a bare
	// "<transformerName>:" with no value registers nothing on its own -
	// only nested option lines that follow do, lazily). Passed through
	// as-is to transform.Entry.TransformerConfig (see
	// fetchAndTransformSchema); each transformer looks up its own options
	// (via transform.Entry.ConfigList) or presence (via
	// transform.Entry.HasTransformer), so unrecognized transformer
	// names/options are simply ignored.
	//
	// "contentIsOutOfSpec" is one such boolean-flag transformer name,
	// consumed by transform.ExtractContent: when true, the kind's
	// content is taken from the schema's top-level properties (minus
	// apiVersion/kind/metadata/status) instead of its "spec" property, for
	// core kinds that have no "spec" of their own (e.g. ConfigMap, Secret,
	// ServiceAccount). It also controls whether the resulting manifest
	// wraps the resource's values in `spec:` at render time (see
	// generateTemplate).
	transformerConfig map[string]map[string][]string
}

// parseResources parses resources.yaml (see resourcesFile and resourceYAML)
// using gopkg.in/yaml.v3's ordinary struct unmarshaling (the same YAML
// dependency used elsewhere, to parse fetched CRD manifests), converting
// each resourceYAML into a resource.
func parseResources(path string) ([]resource, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}

	var file resourcesFile
	if err := yaml.Unmarshal(data, &file); err != nil {
		return nil, fmt.Errorf("parse %s: %w", path, err)
	}

	entries := make([]resource, 0, len(file.Resources))
	for _, r := range file.Resources {
		if r.Name == "" {
			return nil, fmt.Errorf("%s: resource is missing a name", path)
		}
		config, err := buildTransformerConfig(r.Transformer)
		if err != nil {
			return nil, fmt.Errorf("%s: resource %q: transformer: %w", path, r.Name, err)
		}
		entries = append(entries, resource{
			name:              r.Name,
			url:               r.URL,
			apiVersion:        r.APIVersion,
			kind:              r.Kind,
			crdVersion:        r.CRDVersion,
			component:         r.Component,
			transformerConfig: config,
		})
	}
	return entries, nil
}

// buildTransformerConfig normalizes a resourceYAML's raw, untyped
// "transformer:" decode (see resourceYAML.Transformer) into the
// map[transformerName]map[option][]values shape resource.transformerConfig
// and transform.Entry.TransformerConfig expect. Returns nil if raw is empty
// (a bare "transformer:" with nothing under it, or no "transformer:" key at
// all).
func buildTransformerConfig(raw map[string]any) (map[string]map[string][]string, error) {
	config := map[string]map[string][]string{}
	for name, value := range raw {
		switch v := value.(type) {
		case nil:
			// A bare "<name>:" with no value registers nothing on its own;
			// only an explicit boolean value, or a nested options block
			// (see below), does.
			continue
		case bool:
			if v {
				config[name] = map[string][]string{}
			}
		case map[string]any:
			options := map[string][]string{}
			for option, rawList := range v {
				list, ok := rawList.([]any)
				if !ok {
					return nil, fmt.Errorf("%s.%s: expected a list", name, option)
				}
				values := make([]string, 0, len(list))
				for _, item := range list {
					s, ok := item.(string)
					if !ok {
						return nil, fmt.Errorf("%s.%s: expected a list of strings", name, option)
					}
					values = append(values, s)
				}
				options[option] = values
			}
			config[name] = options
		default:
			return nil, fmt.Errorf("%s: unsupported value %#v", name, value)
		}
	}
	if len(config) == 0 {
		return nil, nil
	}
	return config, nil
}
