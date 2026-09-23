package generate

import (
	"fmt"
	"os"

	"resourceschart/generate/transform"

	"gopkg.in/yaml.v3"
)

// resource represents one resource kind declared in resources.yaml, e.g.:
//
//	configMaps:
//	  url: https://raw.githubusercontent.com/kubernetes/kubernetes/master/api/openapi-spec/v3/api__v1_openapi.json
//	  component: io.k8s.api.core.v1.ConfigMap
//	  apiVersion: v1
//	  kind: ConfigMap
//	  transformer:
//	    contentIsOutOfSpec: true
//
// For third-party CRDs whose schema isn't published as part of Kubernetes'
// own OpenAPI v3 spec (e.g. bitnami's SealedSecret), url may instead point
// at the CRD's own YAML manifest, with crdVersion set to the CRD version
// whose spec.versions[].schema.openAPIV3Schema should be extracted and used
// as the kind's schema (see fetchCRDManifestSchema).
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
	// each kind's "base-resources.generic.renderAll" call, without
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

// parseResources parses the restricted YAML shape used by resources.yaml,
// using gopkg.in/yaml.v3 (the same YAML dependency used elsewhere, to parse
// fetched CRD manifests):
//
//	resources:
//	  <name>:
//	    url: <value>
//	    apiVersion: <value>
//	    kind: <value>
//	    crdVersion: <value>           # optional, see resource.crdVersion
//	    component: <value>            # optional, see resource.component
//	    transformer:                  # optional, see resource.transformerConfig
//	      <name>: <true|false>
//	      <name>:
//	        <option>:
//	          - <value>
//
// Parsing is done via yaml.Node (rather than unmarshaling straight into a
// Go map) so that the order resource kinds appear in resources.yaml is
// preserved in the returned slice - Go maps have no defined iteration
// order, and the order kinds appear in is significant: it's the order
// generateTemplate emits each kind's "base-resources.generic.renderAll" call in
// templates/_generated.tpl.
func parseResources(path string) ([]resource, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}

	var doc yaml.Node
	if err := yaml.Unmarshal(data, &doc); err != nil {
		return nil, fmt.Errorf("parse %s: %w", path, err)
	}
	if len(doc.Content) == 0 {
		return nil, nil
	}

	root := doc.Content[0]
	if root.Kind != yaml.MappingNode {
		return nil, fmt.Errorf("%s: expected a top-level mapping", path)
	}

	resourcesNode := mappingValue(root, "resources")
	if resourcesNode == nil || resourcesNode.Kind != yaml.MappingNode {
		return nil, fmt.Errorf(`%s: expected a top-level "resources" mapping`, path)
	}

	entries := make([]resource, 0, len(resourcesNode.Content)/2)
	for i := 0; i < len(resourcesNode.Content); i += 2 {
		name := resourcesNode.Content[i].Value
		e, err := parseResourceNode(name, resourcesNode.Content[i+1])
		if err != nil {
			return nil, fmt.Errorf("%s: resource %q: %w", path, name, err)
		}
		entries = append(entries, e)
	}
	return entries, nil
}

// parseResourceNode parses one <name>: { ... } entry under resources.yaml's
// top-level "resources" mapping into a resource.
func parseResourceNode(name string, node *yaml.Node) (resource, error) {
	if node.Kind != yaml.MappingNode {
		return resource{}, fmt.Errorf("expected a mapping")
	}

	e := resource{name: name}
	for i := 0; i < len(node.Content); i += 2 {
		key, valueNode := node.Content[i].Value, node.Content[i+1]
		switch key {
		case "url":
			e.url = valueNode.Value
		case "apiVersion":
			e.apiVersion = valueNode.Value
		case "kind":
			e.kind = valueNode.Value
		case "crdVersion":
			e.crdVersion = valueNode.Value
		case "component":
			e.component = valueNode.Value
		case "transformer":
			config, err := parseTransformerConfig(valueNode)
			if err != nil {
				return resource{}, fmt.Errorf("transformer: %w", err)
			}
			e.transformerConfig = config
		}
	}
	return e, nil
}

// parseTransformerConfig parses a resource kind's "transformer:" mapping
// (see resource.transformerConfig) into the map[transformerName]map[option][]values
// shape transform.Entry.TransformerConfig expects. Returns nil if node has
// no value at all (a bare "transformer:" with nothing under it).
func parseTransformerConfig(node *yaml.Node) (map[string]map[string][]string, error) {
	if node.Tag == "!!null" {
		return nil, nil
	}
	if node.Kind != yaml.MappingNode {
		return nil, fmt.Errorf("expected a mapping")
	}

	config := map[string]map[string][]string{}
	for i := 0; i < len(node.Content); i += 2 {
		name, valueNode := node.Content[i].Value, node.Content[i+1]
		switch valueNode.Kind {
		case yaml.ScalarNode:
			if valueNode.Tag == "!!null" {
				// A bare "<name>:" with no value registers nothing on its
				// own; only an explicit boolean value, or a nested options
				// block (see below), does.
				continue
			}
			var enabled bool
			if err := valueNode.Decode(&enabled); err != nil {
				return nil, fmt.Errorf("%s: expected a boolean, got %q", name, valueNode.Value)
			}
			if enabled {
				config[name] = map[string][]string{}
			} else {
				delete(config, name)
			}
		case yaml.MappingNode:
			options := map[string][]string{}
			for j := 0; j < len(valueNode.Content); j += 2 {
				option, listNode := valueNode.Content[j].Value, valueNode.Content[j+1]
				var values []string
				if err := listNode.Decode(&values); err != nil {
					return nil, fmt.Errorf("%s.%s: %w", name, option, err)
				}
				options[option] = values
			}
			config[name] = options
		default:
			return nil, fmt.Errorf("%s: unsupported value", name)
		}
	}
	if len(config) == 0 {
		return nil, nil
	}
	return config, nil
}

// mappingValue returns the value node associated with key in a YAML mapping
// node, or nil if node isn't a mapping or has no such key.
func mappingValue(node *yaml.Node, key string) *yaml.Node {
	if node.Kind != yaml.MappingNode {
		return nil
	}
	for i := 0; i < len(node.Content); i += 2 {
		if node.Content[i].Value == key {
			return node.Content[i+1]
		}
	}
	return nil
}
