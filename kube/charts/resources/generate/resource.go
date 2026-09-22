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
//	  contentIsSpec: false
//
// For third-party CRDs whose schema isn't published as part of Kubernetes'
// own OpenAPI v3 spec (e.g. bitnami's SealedSecret), url may instead point
// at the CRD's own YAML manifest, with crdVersion set to the CRD version
// whose spec.versions[].schema.openAPIV3Schema should be extracted and used
// as the kind's schema (see fetchCRDManifestSchema).
type resource struct {
	name          string
	url           string
	apiVersion    string
	kind          string
	contentIsSpec bool     // defaults to true; set contentIsSpec: false in resources.yaml to override
	crdVersion    string   // optional; set to fetch the schema from a CRD manifest (YAML) instead of Kubernetes' own OpenAPI v3 spec
	component     string   // optional; set to the fully-qualified component name (e.g. io.k8s.api.core.v1.ConfigMap) to fetch from a Kubernetes OpenAPI v3 spec document at url (see fetchOpenAPIV3Schema)
	required      []string // top-level required fields, extracted from the upstream k8s schema by stripRequiredTransform
}

// parseCRDs is a minimal parser for the restricted YAML shape used by resources.yaml:
//
//	resources:
//	  <name>:
//	    url: <value>
//	    apiVersion: <value>
//	    kind: <value>
//	    contentIsSpec: <true|false>   # optional, defaults to true
//	    crdVersion: <value>           # optional, see resource.crdVersion
//	    component: <value>            # optional, see resource.component
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

	flush := func() {
		if current != nil {
			entries = append(entries, *current)
			current = nil
		}
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
			current = &resource{name: strings.TrimSuffix(trimmed, ":"), contentIsSpec: true}
		case indent == 4 && current != nil:
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
			case "contentIsSpec":
				current.contentIsSpec = value == "true"
			case "crdVersion":
				current.crdVersion = value
			case "component":
				current.component = value
			}
		}
	}
	flush()

	return entries, nil
}
