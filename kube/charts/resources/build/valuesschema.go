package main

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
)

// generateValuesSchema writes schema/values.schema.json: a JSON Schema
// describing .Values.resources.<kind>.<id> and .Values.defaultValues.<kind>.
// Each kind's instance schema lives in schema/resources/<name>.json (written
// by fetchAndTransformSchema) and has no top-level "required" (see
// stripRequiredTransform), so both .Values.resources.<kind> and
// .Values.defaultValues.<kind> can safely $ref that same single file -
// required-field validation on the merged resource is instead generated
// into templates/_generated.tpl (see resources.generic.requireFields).
//
// NOTE: this is intentionally NOT written to the chart root as
// values.schema.json yet (Helm only auto-validates that exact path), since
// Helm's schema validator doesn't resolve cross-file "$ref" the way we need
// here. Wiring it up as the chart's actual values.schema.json (inlining the
// referenced schemas, or otherwise) is deferred to later.
func generateValuesSchema(dir string, entries []entry) error {
	resourcesProps := map[string]interface{}{}
	defaultValuesProps := map[string]interface{}{}

	for _, e := range entries {
		resourcesProps[e.name] = map[string]interface{}{
			"type":                 "object",
			"description":          fmt.Sprintf("%s instances, keyed by id.", e.kind),
			"additionalProperties": map[string]interface{}{"$ref": "./resources/" + e.name + ".json"},
		}

		defaultValuesProps[e.name] = map[string]interface{}{"$ref": "./resources/" + e.name + ".json"}
	}

	schema := map[string]interface{}{
		"$schema": "https://json-schema.org/draft-07/schema#",
		"type":    "object",
		"properties": map[string]interface{}{
			"resources": map[string]interface{}{
				"type":       "object",
				"properties": resourcesProps,
			},
			"defaultValues": map[string]interface{}{
				"type":       "object",
				"properties": defaultValuesProps,
			},
		},
	}

	out, err := json.MarshalIndent(schema, "", "  ")
	if err != nil {
		return fmt.Errorf("marshal values.schema.json: %w", err)
	}
	out = append(out, '\n')

	dest := filepath.Join(dir, "schema", "values.schema.json")
	fmt.Printf("generating %s\n", dest)
	return os.WriteFile(dest, out, 0o644)
}
