package normalizeIntOrString

import "github.com/becloudless/becloudless/kube/charts/base/templates/resources/mutations"

type NormalizeIntOrString struct{}

func (NormalizeIntOrString) Mutate(schema map[string]any) (mutations.MutationResult, error) {
	mutations.WalkSchemaNodes(schema, func(node map[string]any) {
		if node["x-kubernetes-int-or-string"] != true {
			return
		}
		if anyOf, ok := node["anyOf"]; ok && anyOf != nil {
			return
		}
		node["anyOf"] = []any{
			map[string]any{"type": "integer"},
			map[string]any{"type": "string"},
		}
	})
	return mutations.MutationResult{Schema: schema}, nil
}
