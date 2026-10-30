package itemFields

import (
	"fmt"
	"sort"
	"strings"

	"github.com/becloudless/becloudless/kube/charts/base/templates/resources/mutations"
)

// Item is what is set on the items of an id-keyed map (an array converted by ArraysToMaps).
type Item struct {
	// KeyField is the field of the item that gets the key of the item when the item does not set it, ex: `port` for
	// the ports of the Cilium policies, `ports.443: {}` is `ports: [{port: "443"}]`.
	KeyField string `yaml:"keyField"`
	// Defaults are the fields set on the item when it does not set them, ex: `protocol: TCP`.
	Defaults map[string]string `yaml:"defaults"`
}

// ItemFields declares, by schema path of an array converted to an id-keyed map (see ArraysToMaps), the fields given
// to its items when they do not set them (per-resource-kind in resources.yaml as mutations.itemFields):
//
//	mutations:
//	  itemFields:
//	    egress.toPorts.ports:
//	      keyField: port
//	      defaults: {protocol: TCP}
//
// It lets an item be written as its id only, ex: `fields.password: {}` for a StringSecret. The schema is left as is
// (the fields required by the items are checked at render time, once this is applied, see Required), it only checks
// that the paths and the fields exist. The paths are reported via MutationResult.TemplateArgs (key "itemFields"), for
// templates/mutations/itemFields/_itemFields.tpl, which runs before the check of the required fields and the
// conversion of the maps back to arrays.
type ItemFields map[string]Item

func (m ItemFields) Mutate(schema map[string]any) (mutations.MutationResult, error) {
	if len(m) == 0 {
		return mutations.MutationResult{Schema: schema}, nil
	}

	found := map[string]map[string]any{}
	mutations.WalkSchemaNodesWithPath(schema, "", func(node map[string]any, path string) {
		if _, configured := m[path]; !configured {
			return
		}
		if items, ok := node["additionalProperties"].(map[string]any); ok {
			if props, ok := items["properties"].(map[string]any); ok {
				found[path] = props
			}
		}
	})

	paths := make([]string, 0, len(m))
	for path := range m {
		paths = append(paths, path)
	}
	sort.Strings(paths)

	entries := make([]string, 0, len(paths))
	for _, path := range paths {
		item := m[path]
		props, ok := found[path]
		if !ok {
			return mutations.MutationResult{}, fmt.Errorf("itemFields %q: not an array of objects", path)
		}
		fields := make([]string, 0, len(item.Defaults)+1)
		if item.KeyField != "" {
			fields = append(fields, item.KeyField)
		}
		defaultFields := make([]string, 0, len(item.Defaults))
		for field := range item.Defaults {
			defaultFields = append(defaultFields, field)
		}
		sort.Strings(defaultFields)
		fields = append(fields, defaultFields...)
		for _, field := range fields {
			if _, ok := props[field]; !ok {
				return mutations.MutationResult{}, fmt.Errorf("itemFields %q: the items have no property %q", path, field)
			}
		}

		defaults := make([]string, 0, len(defaultFields))
		for _, field := range defaultFields {
			defaults = append(defaults, fmt.Sprintf("%q %q", field, item.Defaults[field]))
		}
		entries = append(entries, fmt.Sprintf(`%q (dict "keyField" %q "defaults" (dict %s))`, path, item.KeyField, strings.Join(defaults, " ")))
	}

	return mutations.MutationResult{
		Schema:       schema,
		TemplateArgs: map[string]string{"itemFields": fmt.Sprintf("(dict %s)", strings.Join(entries, " "))},
	}, nil
}
