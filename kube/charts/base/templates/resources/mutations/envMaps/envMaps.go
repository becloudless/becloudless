package envMaps

import (
	"fmt"
	"sort"
	"strings"

	"github.com/becloudless/becloudless/kube/charts/base/templates/resources/mutations"
)

// EnvMaps converts every container-style "env" array of the schema (an array
// of EnvVar-like objects: "name" + "value"/"valueFrom") into a map where the
// KEY is the environment variable name and the VALUE is either:
//
//   - a scalar (string, number, boolean): the variable's "value"
//
//   - an object: the variable's "valueFrom" (secretKeyRef, configMapKeyRef...)
//
//     env:
//     TZ: europe/paris
//     DB_PASSWORD:
//     secretKeyRef:
//     name: db
//     key: password
//
// It must run BEFORE ArraysToMaps, which would otherwise turn the same node
// into an id-keyed map of full EnvVar objects. Converted schema paths are
// reported via MutationResult.TemplateArgs (key "envPaths") so
// templates/mutations/_mapsToEnv.tpl can reverse the conversion at render time.
type EnvMaps struct{}

func (m EnvMaps) Mutate(schema map[string]any) (mutations.MutationResult, error) {
	var convertedPaths []string
	mutations.WalkSchemaNodesWithPath(schema, "", func(node map[string]any, path string) {
		if path != "env" && !strings.HasSuffix(path, ".env") {
			return
		}
		if convertEnvNodeToMap(node) {
			convertedPaths = append(convertedPaths, path)
		}
	})

	sort.Strings(convertedPaths)
	quoted := make([]string, len(convertedPaths))
	for i, path := range convertedPaths {
		quoted[i] = fmt.Sprintf("%q", path)
	}

	return mutations.MutationResult{
		Schema:       schema,
		TemplateArgs: map[string]string{"envPaths": fmt.Sprintf("(list %s)", strings.Join(quoted, " "))},
	}, nil
}

func convertEnvNodeToMap(node map[string]any) bool {
	if !mutations.SchemaTypeIncludes(node["type"], "array") {
		return false
	}
	items, ok := node["items"].(map[string]any)
	if !ok {
		return false
	}
	props, ok := items["properties"].(map[string]any)
	if !ok {
		return false
	}
	valueFrom, ok := props["valueFrom"].(map[string]any)
	if _, hasName := props["name"]; !ok || !hasName {
		return false
	}
	if _, hasValue := props["value"]; !hasValue {
		return false
	}

	node["type"] = mutations.ReplaceSchemaType(node["type"], "array", "object")
	node["additionalProperties"] = map[string]any{
		"anyOf": []any{
			map[string]any{
				"type":        []any{"string", "number", "boolean"},
				"description": "Value of the environment variable.",
			},
			valueFrom,
		},
	}
	delete(node, "items")
	delete(node, "minItems")
	delete(node, "maxItems")
	delete(node, "uniqueItems")
	delete(node, "x-kubernetes-list-type")
	delete(node, "x-kubernetes-list-map-keys")
	return true
}
