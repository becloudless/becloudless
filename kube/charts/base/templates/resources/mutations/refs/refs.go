package refs

import (
	"fmt"
	"maps"
	"sort"
	"strings"

	"github.com/becloudless/becloudless/kube/charts/base/templates/resources/mutations"
)

// Pattern is what the schema asks of a reference: the prefix `ref:` and an identifier. What it points to is checked at render
// time (see templates/mutations/refs/_refs.tpl), where the resources are known.
const Pattern = `^ref:.+$`

// Projections are what a reference can become, and if it becomes an object (true) or a string (false). They are implemented by
// `base.lib.refs.project`.
var Projections = map[string]bool{
	"name":                  false, // the name of the resource
	"secretName":            false, // the name of the Secret the resource is, or makes (certificates, external secrets)
	"gatewayRef":            true,  // {group, kind, name[, namespace]} of a Gateway API parent (a ListenerSet, a Gateway)
	"roleRef":               true,  // {apiGroup, kind, name} of a Role or a ClusterRole
	"serviceAccountSubject": true,  // {kind, name, namespace} of a ServiceAccount, as the subject of a binding
	"podSelector":           true,  // {matchLabels} of the pods of a workload
	"helmReleaseRef":        true,  // {name[, namespace]} of a Flux HelmRelease
	"secretStoreRef":        true,  // {name, kind} of a SecretStore or a ClusterSecretStore of external-secrets
}

// Ref is a position of a resource that accepts a reference to another resource (`ref:<id>`).
type Ref struct {
	// Kinds are the kinds (the names of resources.yaml, ex: `services`) the reference can point to. A reference to the only kind
	// is the id (`ref:web`), else it has the kind too (`ref:deployments/web`).
	Kinds []string `yaml:"kinds"`
	// As is what the reference becomes, one of Projections.
	As string `yaml:"as"`
}

// Refs declares, by schema path, the fields that accept a reference to another resource of the release (or of a sibling
// release, `ref:<kind>/<id>`, with `@<release>` when the id is ambiguous) instead of its full description (per-resource-kind in resources.yaml as mutations.refs):
//
//	mutations:
//	  refs:
//	    rules.backendRefs.name: {kinds: [services], as: name}
//	    parentRefs: {kinds: [listenerSets, gateways], as: gatewayRef}
//
// A string position accepts `ref:<id>` (ex: `name: ref:web`) and becomes the string. An object position accepts it as the
// whole object, a map of objects (usually an array converted to an id-keyed map, see ArraysToMaps) accepts it for its entries
// and as a list too (`parentRefs: [ref:listenerSets/web]`, the id is the key of the entry). An array that is kept as is (see
// ArraysToMaps ignore) accepts it for its items (`dependsOn: [ref:db, {name: other, namespace: elsewhere}]`). The resolution is done at render
// time, a reference that does not resolve fails, see templates/mutations/refs/_refs.tpl. The paths are reported via
// MutationResult.TemplateArgs (key "refs").
type Refs map[string]Ref

func (m Refs) Mutate(schema map[string]any) (mutations.MutationResult, error) {
	if len(m) == 0 {
		return mutations.MutationResult{Schema: schema}, nil
	}

	// the nodes visited for a path, the last one is the outermost (the map of the entries is visited after the entries). The empty
	// nodes are skipped: a `oneOf` of `required` (ex: the endpointSelector or the nodeSelector of a Cilium policy) names the
	// properties it needs with `{}`, visited after the real one, which would else be taken for the outermost.
	found := map[string][]map[string]any{}
	mutations.WalkSchemaNodesWithPath(schema, "", func(node map[string]any, path string) {
		if _, configured := m[path]; configured && describesValue(node) {
			found[path] = append(found[path], node)
		}
	})

	paths := make([]string, 0, len(m))
	for path := range m {
		paths = append(paths, path)
	}
	sort.Strings(paths)

	entries := make([]string, 0, len(paths))
	for _, path := range paths {
		ref := m[path]
		object, known := Projections[ref.As]
		if !known {
			return mutations.MutationResult{}, fmt.Errorf("refs %q: unknown projection %q", path, ref.As)
		}
		if len(ref.Kinds) == 0 {
			return mutations.MutationResult{}, fmt.Errorf("refs %q: kinds are required", path)
		}
		nodes := found[path]
		if len(nodes) == 0 {
			return mutations.MutationResult{}, fmt.Errorf("refs %q: not in the schema", path)
		}

		if object {
			relaxObject(nodes[len(nodes)-1])
		} else {
			relaxed := false
			for _, node := range nodes {
				if mutations.SchemaTypeIncludes(node["type"], "string") {
					relax(node)
					relaxed = true
				}
			}
			if !relaxed {
				return mutations.MutationResult{}, fmt.Errorf("refs %q: not a string", path)
			}
		}

		kinds := make([]string, len(ref.Kinds))
		for i, kind := range ref.Kinds {
			kinds[i] = fmt.Sprintf("%q", kind)
		}
		entries = append(entries, fmt.Sprintf(`%q (dict "kinds" (list %s) "as" %q)`, path, strings.Join(kinds, " "), ref.As))
	}

	return mutations.MutationResult{
		Schema:       schema,
		TemplateArgs: map[string]string{"refs": fmt.Sprintf("(dict %s)", strings.Join(entries, " "))},
	}, nil
}

func refNode() map[string]any {
	return map[string]any{"type": "string", "pattern": Pattern}
}

// describesValue reports whether a node describes a value (a type, properties, entries or items), as opposed to the `{}` a
// `oneOf` of `required` uses to name a property.
func describesValue(node map[string]any) bool {
	for _, key := range []string{"type", "properties", "additionalProperties", "items"} {
		if _, ok := node[key]; ok {
			return true
		}
	}
	return false
}

// relax makes the node accept a reference next to what it accepts.
func relax(node map[string]any) {
	original := maps.Clone(node)
	clear(node)
	if description, ok := original["description"]; ok {
		node["description"] = description
	}
	node["anyOf"] = []any{refNode(), original}
}

// relaxObject makes an object accept a reference. The map of entries accepts it for each entry, and as a list of references.
// An array (left as is, see ArraysToMaps) accepts it for each of its items.
func relaxObject(node map[string]any) {
	if items, isArray := node["items"].(map[string]any); isArray && mutations.SchemaTypeIncludes(node["type"], "array") {
		node["items"] = map[string]any{"anyOf": []any{refNode(), items}}
		return
	}
	entry, isMap := node["additionalProperties"].(map[string]any)
	if !isMap {
		relax(node)
		return
	}
	node["type"] = []any{"object", "array"}
	node["items"] = refNode()
	node["additionalProperties"] = map[string]any{"anyOf": []any{refNode(), entry}}
}
