package listShorthands

import (
	"fmt"
	"sort"
	"strings"

	"github.com/becloudless/becloudless/kube/charts/base/templates/resources/mutations"
)

// Shorthand is how a list of scalars given for a map stands for one entry of that map.
type Shorthand struct {
	// Key is the key of the entry of the map the scalars go to.
	Key string `yaml:"key"`
	// Field is the property of that entry that gets the scalars, as the keys of its map (see ItemFields to give them
	// their fields).
	Field string `yaml:"field"`
}

// ListShorthands declares, by schema path of a map (usually an array converted to an id-keyed map, see ArraysToMaps),
// that it can be given as a plain list of scalars instead (per-resource-kind in resources.yaml as
// mutations.listShorthands):
//
//	mutations:
//	  listShorthands:
//	    egress.toPorts: {key: main, field: ports}
//
// `toPorts: [443, 80]` is then `toPorts: {main: {ports: {"443": {}, "80": {}}}}`. The schema of the map accepts the
// list too (of integers or strings), the expansion is done at render time, see
// templates/mutations/listShorthands/_listShorthands.tpl, which runs before ItemFields (it gives the fields of the
// entries made, ex: the port and the TCP protocol of the ports of a Cilium rule) and before the check of the required
// fields. A list that has maps in it is left as is, it is a real list of entries. The paths are reported via
// MutationResult.TemplateArgs (key "listShorthands").
type ListShorthands map[string]Shorthand

func (m ListShorthands) Mutate(schema map[string]any) (mutations.MutationResult, error) {
	if len(m) == 0 {
		return mutations.MutationResult{Schema: schema}, nil
	}

	found := map[string]map[string]any{}
	mutations.WalkSchemaNodesWithPath(schema, "", func(node map[string]any, path string) {
		if _, configured := m[path]; !configured {
			return
		}
		if _, ok := node["additionalProperties"].(map[string]any); ok {
			found[path] = node
		}
	})

	paths := make([]string, 0, len(m))
	for path := range m {
		paths = append(paths, path)
	}
	sort.Strings(paths)

	entries := make([]string, 0, len(paths))
	for _, path := range paths {
		shorthand := m[path]
		node, ok := found[path]
		if !ok {
			return mutations.MutationResult{}, fmt.Errorf("listShorthands %q: not a map of objects", path)
		}
		if shorthand.Key == "" || shorthand.Field == "" {
			return mutations.MutationResult{}, fmt.Errorf("listShorthands %q: key and field are required", path)
		}
		entry, _ := node["additionalProperties"].(map[string]any)
		props, _ := entry["properties"].(map[string]any)
		if _, ok := props[shorthand.Field].(map[string]any); !ok {
			return mutations.MutationResult{}, fmt.Errorf("listShorthands %q: the entries have no property %q", path, shorthand.Field)
		}

		node["type"] = []any{"object", "array"}
		node["items"] = map[string]any{"type": []any{"integer", "string"}}
		entries = append(entries, fmt.Sprintf(`%q (dict "key" %q "field" %q)`, path, shorthand.Key, shorthand.Field))
	}

	return mutations.MutationResult{
		Schema:       schema,
		TemplateArgs: map[string]string{"listShorthands": fmt.Sprintf("(dict %s)", strings.Join(entries, " "))},
	}, nil
}
