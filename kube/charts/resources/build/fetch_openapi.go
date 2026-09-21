package main

import (
	"encoding/json"
	"fmt"
	"io"
	"net/http"
)

// openapiDocCache caches parsed Kubernetes OpenAPI v3 spec documents by
// url for the lifetime of a single build run, since several kinds are
// often declared in the same per-group-version document (e.g.
// Deployment/StatefulSet/DaemonSet all live in apis__apps__v1_openapi.json).
var openapiDocCache = map[string]map[string]interface{}{}

// fetchOpenAPIDocument fetches and parses (or returns from cache) the
// Kubernetes OpenAPI v3 spec document at url.
func fetchOpenAPIDocument(client *http.Client, url string) (map[string]interface{}, error) {
	if doc, ok := openapiDocCache[url]; ok {
		return doc, nil
	}

	resp, err := client.Get(url)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("unexpected status %s", resp.Status)
	}

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, err
	}

	var doc map[string]interface{}
	if err := json.Unmarshal(body, &doc); err != nil {
		return nil, fmt.Errorf("parse OpenAPI document: %w", err)
	}

	openapiDocCache[url] = doc
	return doc, nil
}

// fetchOpenAPIV3Schema fetches url - a Kubernetes OpenAPI v3 spec document
// such as api/openapi-spec/v3/api__v1_openapi.json, published directly by
// the kubernetes/kubernetes project - and returns the schema declared for
// component (e.g. "io.k8s.api.core.v1.ConfigMap" or
// "io.k8s.api.apps.v1.Deployment"), with every
// "$ref": "#/components/schemas/<name>" pointer found anywhere within it
// recursively resolved (inlined) against the same document's
// components.schemas map.
//
// This lets resources.yaml treat Kubernetes' own upstream OpenAPI v3 spec as the
// source of truth for built-in kinds, instead of a third-party pre-flattened
// JSON schema mirror (e.g. yannh/kubernetes-json-schema).
func fetchOpenAPIV3Schema(client *http.Client, url, component string) (map[string]interface{}, error) {
	doc, err := fetchOpenAPIDocument(client, url)
	if err != nil {
		return nil, err
	}

	components, _ := doc["components"].(map[string]interface{})
	schemas, _ := components["schemas"].(map[string]interface{})
	if schemas == nil {
		return nil, fmt.Errorf("%s: no components.schemas found", url)
	}

	root, ok := schemas[component].(map[string]interface{})
	if !ok {
		return nil, fmt.Errorf("%s: component %q not found", url, component)
	}

	resolved := map[string]map[string]interface{}{}
	out, _ := resolveOpenAPIRefs(root, schemas, resolved, map[string]bool{}).(map[string]interface{})
	return out, nil
}

const openAPISchemaRefPrefix = "#/components/schemas/"

// resolveOpenAPIRefs recursively inlines every "$ref": "#/components/schemas/<name>"
// pointer found in node, replacing each one with a deep copy of the
// referenced schema (itself recursively resolved the same way). resolved
// memoizes the fully-resolved form of each component name so it's only
// computed once even if referenced from many places (e.g. ObjectMeta,
// Quantity), while still handing back an independent deep copy to each call
// site to avoid aliasing the same map across unrelated positions in the
// resulting schema tree. inProgress guards against reference cycles by
// substituting a permissive placeholder schema instead of recursing forever.
func resolveOpenAPIRefs(node interface{}, schemas map[string]interface{}, resolved map[string]map[string]interface{}, inProgress map[string]bool) interface{} {
	switch v := node.(type) {
	case map[string]interface{}:
		if ref, ok := v["$ref"].(string); ok && len(v) == 1 {
			name := ref
			if len(ref) > len(openAPISchemaRefPrefix) && ref[:len(openAPISchemaRefPrefix)] == openAPISchemaRefPrefix {
				name = ref[len(openAPISchemaRefPrefix):]
			}
			if r, ok := resolved[name]; ok {
				return deepCopyJSON(r)
			}
			if inProgress[name] {
				// Reference cycle: break it with a permissive placeholder
				// rather than recursing forever.
				return map[string]interface{}{}
			}
			target, ok := schemas[name].(map[string]interface{})
			if !ok {
				return map[string]interface{}{}
			}
			inProgress[name] = true
			out, _ := resolveOpenAPIRefs(target, schemas, resolved, inProgress).(map[string]interface{})
			delete(inProgress, name)
			resolved[name] = out
			return deepCopyJSON(out)
		}

		out := make(map[string]interface{}, len(v))
		for k, val := range v {
			out[k] = resolveOpenAPIRefs(val, schemas, resolved, inProgress)
		}
		return out
	case []interface{}:
		out := make([]interface{}, len(v))
		for i, val := range v {
			out[i] = resolveOpenAPIRefs(val, schemas, resolved, inProgress)
		}
		return out
	default:
		return v
	}
}

// deepCopyJSON returns an independent deep copy of a JSON-decoded value
// (as produced by encoding/json into map[string]interface{}/[]interface{}).
func deepCopyJSON(v interface{}) interface{} {
	switch t := v.(type) {
	case map[string]interface{}:
		out := make(map[string]interface{}, len(t))
		for k, val := range t {
			out[k] = deepCopyJSON(val)
		}
		return out
	case []interface{}:
		out := make([]interface{}, len(t))
		for i, val := range t {
			out[i] = deepCopyJSON(val)
		}
		return out
	default:
		return v
	}
}
