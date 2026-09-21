package main

// flattenAllOfTransform recursively collapses "allOf" schema nodes (the
// pattern OpenAPI-v3-derived schemas commonly use to combine a $ref with
// sibling keywords, e.g. {"allOf": [{"$ref": "..."}], "description": "..."})
// into a single flat object schema, merging each branch's "properties"
// (node's own properties win on conflicts) and "required" (union, deduped)
// and copying over any other branch keyword not already set on the node.
// This keeps downstream transformers - which only look at a node's own
// "type"/"properties"/"items"/"additionalProperties" - working the same way
// for schemas fetched from Kubernetes' OpenAPI v3 spec (see
// fetchOpenAPIV3Schema) as they do for the already-flattened schemas used
// elsewhere (plain JSON schema mirrors, CRD manifests).
func flattenAllOfTransform(schema map[string]interface{}, _ *entry) (map[string]interface{}, error) {
	walkSchemaNodes(schema, flattenAllOfNode)
	return schema, nil
}

func flattenAllOfNode(node map[string]interface{}) {
	allOf, ok := node["allOf"].([]interface{})
	if !ok || len(allOf) == 0 {
		return
	}
	delete(node, "allOf")
	for _, item := range allOf {
		branch, ok := item.(map[string]interface{})
		if !ok {
			continue
		}
		mergeAllOfBranch(node, branch)
	}
}

// mergeAllOfBranch merges branch (one "allOf" item, already recursively
// flattened by the time it's visited, since walkSchemaNodes is post-order)
// into node in place.
func mergeAllOfBranch(node, branch map[string]interface{}) {
	if props, ok := branch["properties"].(map[string]interface{}); ok {
		merged := map[string]interface{}{}
		for k, v := range props {
			merged[k] = v
		}
		if existing, ok := node["properties"].(map[string]interface{}); ok {
			for k, v := range existing {
				merged[k] = v // node's own properties take precedence
			}
		}
		node["properties"] = merged
	}

	if req, ok := branch["required"].([]interface{}); ok {
		seen := map[string]bool{}
		var out []interface{}
		if existing, ok := node["required"].([]interface{}); ok {
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

// arraysToMapsTransform recursively converts every array-type schema node
// that declares an "items" schema into an object/map keyed by an arbitrary
// string id, in line with this chart's convention of representing
// collections as maps keyed by id (e.g. .Values.resources.<kind>.<id>)
// rather than as arrays. The array's "items" schema becomes the map's
// "additionalProperties" schema, and array-only keywords are dropped.
func arraysToMapsTransform(schema map[string]interface{}, _ *entry) (map[string]interface{}, error) {
	walkSchemaNodes(schema, convertArrayNodeToMap)
	return schema, nil
}

func convertArrayNodeToMap(node map[string]interface{}) {
	if !schemaTypeIncludes(node["type"], "array") {
		return
	}
	items, ok := node["items"].(map[string]interface{})
	if !ok {
		return
	}

	node["type"] = replaceSchemaType(node["type"], "array", "object")
	node["additionalProperties"] = items
	delete(node, "items")
	delete(node, "minItems")
	delete(node, "maxItems")
	delete(node, "uniqueItems")
	delete(node, "x-kubernetes-list-type")
	delete(node, "x-kubernetes-list-map-keys")
}

// additionalPropertiesFalseTransform recursively sets
// "additionalProperties": false on every object-type schema node that
// declares its own "properties" but doesn't already constrain
// additionalProperties (via "additionalProperties" or "patternProperties"),
// closing the schema against unknown/typo'd fields. Nodes that already
// declare "additionalProperties" (e.g. free-form maps like ConfigMap's
// "data", or maps produced by arraysToMapsTransform) are left untouched.
func additionalPropertiesFalseTransform(schema map[string]interface{}, _ *entry) (map[string]interface{}, error) {
	walkSchemaNodes(schema, func(node map[string]interface{}) {
		if !schemaTypeIncludes(node["type"], "object") {
			return
		}
		if _, hasProps := node["properties"]; !hasProps {
			return
		}
		if _, ok := node["additionalProperties"]; ok {
			return
		}
		if _, ok := node["patternProperties"]; ok {
			return
		}
		node["additionalProperties"] = false
	})
	return schema, nil
}
