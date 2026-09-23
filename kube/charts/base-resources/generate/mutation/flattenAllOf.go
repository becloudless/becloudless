package mutation

import "maps"

// FlattenAllOf recursively collapses "allOf" schema nodes (the pattern
// OpenAPI-v3-derived schemas commonly use to combine a $ref with sibling
// keywords, e.g. {"allOf": [{"$ref": "..."}], "description": "..."}) into a
// single flat object schema, merging each branch's "properties" (node's own
// properties win on conflicts) and "required" (union, deduped) and copying
// over any other branch keyword not already set on the node. This keeps
// downstream mutations - which only look at a node's own
// "type"/"properties"/"items"/"additionalProperties" - working the same way
// for schemas fetched from Kubernetes' OpenAPI v3 spec as they do for the
// already-flattened schemas used elsewhere (plain JSON schema mirrors, CRD
// manifests).
type FlattenAllOf struct{}

func (FlattenAllOf) Mutate(schema map[string]any, _ *Entry) (map[string]any, error) {
	walkSchemaNodes(schema, flattenAllOfNode)
	return schema, nil
}

func flattenAllOfNode(node map[string]any) {
	allOf, ok := node["allOf"].([]any)
	if !ok || len(allOf) == 0 {
		return
	}
	delete(node, "allOf")
	for _, item := range allOf {
		branch, ok := item.(map[string]any)
		if !ok {
			continue
		}
		mergeAllOfBranch(node, branch)
	}
}

// mergeAllOfBranch merges branch (one "allOf" item, already recursively
// flattened by the time it's visited, since walkSchemaNodes is post-order)
// into node in place.
func mergeAllOfBranch(node, branch map[string]any) {
	if props, ok := branch["properties"].(map[string]any); ok {
		merged := map[string]any{}
		maps.Copy(merged, props)
		if existing, ok := node["properties"].(map[string]any); ok {
			// node's own properties take precedence
			maps.Copy(merged, existing)
		}
		node["properties"] = merged
	}

	if req, ok := branch["required"].([]any); ok {
		seen := map[string]bool{}
		var out []any
		if existing, ok := node["required"].([]any); ok {
			for _, r := range existing {
				if s, _ := r.(string); s != "" && !seen[s] {
					seen[s] = true
					out = append(out, r)
				}
			}
		}
		for _, r := range req {
			if s, _ := r.(string); s != "" && !seen[s] {
				seen[s] = true
				out = append(out, r)
			}
		}
		node["required"] = out
	}

	for _, key := range []string{"type", "additionalProperties", "items", "format", "enum", "pattern", "minLength", "maxLength", "minimum", "maximum", "x-kubernetes-int-or-string"} {
		if _, exists := node[key]; exists {
			continue
		}
		if v, ok := branch[key]; ok {
			node[key] = v
		}
	}
}
