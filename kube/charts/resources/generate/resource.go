package generate

import (
	"os"
	"strings"
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
	crdVersion string   // optional; set to fetch the schema from a CRD manifest (YAML) instead of Kubernetes' own OpenAPI v3 spec
	component  string   // optional; set to the fully-qualified component name (e.g. io.k8s.api.core.v1.ConfigMap) to fetch from a Kubernetes OpenAPI v3 spec document at url (see fetchOpenAPIV3Schema)
	required   []string // top-level required fields, extracted from the upstream k8s schema by stripRequiredTransform

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

// parseCRDs is a minimal parser for the restricted YAML shape used by resources.yaml:
//
//	resources:
//	  <name>:
//	    url: <value>
//	    apiVersion: <value>
//	    kind: <value>
//	    crdVersion: <value>           # optional, see resource.crdVersion
//	    component: <value>            # optional, see resource.component
//	    transformer:                  # optional, see resource.transformerConfig
//	      <name>:
//	        <option>:
//	          - <value>
//
// It avoids pulling in a YAML dependency for parsing this file itself
// (gopkg.in/yaml.v3 is used elsewhere, to parse fetched CRD manifests).
func parseCRDs(path string) ([]resource, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}

	var entries []resource
	var current *resource
	var currentTransformer string
	var currentOption string

	flush := func() {
		if current != nil {
			entries = append(entries, *current)
			current = nil
		}
		currentTransformer = ""
		currentOption = ""
	}

	for _, rawLine := range strings.Split(string(data), "\n") {
		line := strings.TrimRight(rawLine, " \t\r")
		if strings.TrimSpace(line) == "" || strings.HasPrefix(strings.TrimSpace(line), "#") {
			continue
		}

		indent := len(line) - len(strings.TrimLeft(line, " "))
		trimmed := strings.TrimSpace(line)

		switch {
		case indent == 0:
			// top-level key, e.g. "resources:" — nothing to do.
			continue
		case indent == 2 && strings.HasSuffix(trimmed, ":"):
			flush()
			current = &resource{name: strings.TrimSuffix(trimmed, ":")}
		case indent == 4 && current != nil:
			currentTransformer = ""
			currentOption = ""
			if trimmed == "transformer:" {
				continue
			}
			key, value, ok := strings.Cut(trimmed, ":")
			if !ok {
				continue
			}
			value = strings.TrimSpace(value)
			switch strings.TrimSpace(key) {
			case "url":
				current.url = value
			case "apiVersion":
				current.apiVersion = value
			case "kind":
				current.kind = value
			case "crdVersion":
				current.crdVersion = value
			case "component":
				current.component = value
			}
		case indent == 6 && current != nil:
			// transformer name, e.g. "arraysToMaps:" (a section header with
			// nested options below), or a boolean flag like
			// "contentIsOutOfSpec: true" / "contentIsOutOfSpec: false",
			// under "transformer:". An explicit "true" registers the
			// transformer immediately (visible to
			// transform.Entry.HasTransformer even with no options); an
			// explicit "false" ensures it's absent. A bare "<name>:" with
			// no value isn't enough to register it on its own - only
			// nested option lines that follow (see the indent == 8/10
			// cases below) do that lazily.
			key, value, ok := strings.Cut(trimmed, ":")
			if !ok {
				continue
			}
			currentTransformer = strings.TrimSpace(key)
			currentOption = ""
			value = strings.TrimSpace(value)
			switch value {
			case "true":
				if current.transformerConfig == nil {
					current.transformerConfig = map[string]map[string][]string{}
				}
				if current.transformerConfig[currentTransformer] == nil {
					current.transformerConfig[currentTransformer] = map[string][]string{}
				}
			case "false":
				delete(current.transformerConfig, currentTransformer)
			}
		case indent == 8 && current != nil && currentTransformer != "" && strings.HasSuffix(trimmed, ":"):
			// option name, e.g. "ignore:" under a transformer name.
			currentOption = strings.TrimSuffix(trimmed, ":")
		case indent == 10 && current != nil && currentTransformer != "" && currentOption != "" && strings.HasPrefix(trimmed, "- "):
			value := strings.TrimSpace(strings.TrimPrefix(trimmed, "- "))
			if value == "" {
				continue
			}
			if current.transformerConfig == nil {
				current.transformerConfig = map[string]map[string][]string{}
			}
			if current.transformerConfig[currentTransformer] == nil {
				current.transformerConfig[currentTransformer] = map[string][]string{}
			}
			current.transformerConfig[currentTransformer][currentOption] = append(current.transformerConfig[currentTransformer][currentOption], value)
		}
	}
	flush()

	return entries, nil
}
