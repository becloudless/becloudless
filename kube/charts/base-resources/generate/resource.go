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
	Name       string         `yaml:"name"`
	URL        string         `yaml:"url"`
	APIVersion string         `yaml:"apiVersion"`
	Kind       string         `yaml:"kind"`
	CRDVersion string         `yaml:"crdVersion"` // optional; set to fetch the schema from a CRD manifest (YAML) instead of Kubernetes' own OpenAPI v3 spec
	Component  string         `yaml:"component"`  // optional; set to the fully-qualified component name (e.g. io.k8s.api.core.v1.ConfigMap) to fetch from a Kubernetes OpenAPI v3 spec document at URL (see fetchOpenAPIV3Schema)
	Mutations  map[string]any `yaml:"mutations"`

	// templateArgs holds the named, render-time template arguments the
	// mutation pipeline contributed for this resource kind (see
	// mutation.Entry.TemplateArgs and mutation.Entry.AddTemplateArg),
	// e.g. "required", "contentIsSpec", "stringifyFields". Populated from
	// mutation.Entry.TemplateArgs after running the pipeline (see
	// fetchAndTransformSchema) and consumed by generateTemplate to build
	// each kind's "base-resources.renderResourceKind" call, without
	// generateTemplate needing to know about specific mutation names.
	templateArgs []mutation.TemplateArg

	// mutationConfig holds optional per-mutation configuration for this
	// resource kind, declared in resources.yaml as a nested "mutations"
	// block:
	//
	//	mutations:
	//	  <mutationName>: <true|false> # boolean flag
	//	  <mutationName>:
	//	    <option>:
	//	      - value1
	//	      - value2
	//
	// Keyed by mutation name, then option name; the value is the list of
	// declared items. A mutation name may also be declared with an
	// explicit boolean value (e.g. "contentIsOutOfSpec: true"), instead of a
	// nested options block, purely to mark its presence for the given kind;
	// its map entry is created (just empty) when the value is exactly
	// "true", and left absent/removed when exactly "false" (a bare
	// "<mutationName>:" with no value registers nothing on its own - only
	// nested option lines that follow do, lazily). Passed through as-is to
	// mutation.Entry.MutationConfig (see fetchAndTransformSchema); each
	// mutation looks up its own options (via mutation.Entry.ConfigList) or
	// presence (via mutation.Entry.HasMutation), so unrecognized mutation
	// names/options are simply ignored.
	//
	// "contentIsOutOfSpec" is one such boolean-flag mutation name, consumed
	// by mutation.ExtractContent: when true, the kind's content is taken
	// from the schema's top-level properties (minus
	// apiVersion/kind/metadata/status) instead of its "spec" property, for
	// core kinds that have no "spec" of their own (e.g. ConfigMap, Secret,
	// ServiceAccount). It also controls whether the resulting manifest
	// wraps the resource's values in `spec:` at render time (see
	// generateTemplate).
	mutationConfig map[string]map[string][]string
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
		config, err := buildMutationConfig(file.Resources[i].Mutations)
		if err != nil {
			return resourcesFile{}, fmt.Errorf("%s: resource %q: mutations: %w", path, file.Resources[i].Name, err)
		}
		file.Resources[i].mutationConfig = config
	}
	return file, nil
}

// buildMutationConfig normalizes a resource's raw, untyped "mutations:"
// decode (see resource.Mutations) into the

// map[mutationName]map[option][]values shape resource.mutationConfig
// and mutation.Entry.MutationConfig expect. Returns nil if raw is empty
// (a bare "mutations:" with nothing under it, or no "mutations:" key at
// all).
func buildMutationConfig(raw map[string]any) (map[string]map[string][]string, error) {
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
