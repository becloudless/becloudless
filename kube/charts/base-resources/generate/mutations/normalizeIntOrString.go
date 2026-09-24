package mutations

type NormalizeIntOrString struct{}

func (NormalizeIntOrString) Mutate(schema map[string]any) (MutationResult, error) {
	walkSchemaNodes(schema, func(node map[string]any) {
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
	return MutationResult{Schema: schema}, nil
}
