package generate

import (
	"embed"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
)

//go:embed valuesSchemaBase.json
var valuesSchemaBaseFS embed.FS

// loadValuesSchemaBase decodes the static skeleton shared by
// buildValuesSchema and generateChartValuesSchema: the "global" passthrough,
// and the "resources"/"defaults" structure (including the
// defaults.metadata.* fields), everything except the per-kind schemas built
// from resources.yaml, which callers fill in via setResourcesProps. A fresh
// copy is decoded on every call so callers can freely mutate the returned
// map without affecting each other.
//
// properties.global is a plain "type": "object" with no further
// constraints: Helm always injects a top-level "global" key (default {})
// into every chart's .Values, even if the parent chart never sets one - it
// must stay allowed here or the root "additionalProperties": false rejects
// every values file outright.
//
// properties.defaults.properties.metadata holds global metadata defaults,
// applied across every resource kind (below defaults.resources.<kind> and
// the resource's own values in merge precedence - see
// base-resources.computeMetadata).
func loadValuesSchemaBase() (map[string]interface{}, error) {
	data, err := valuesSchemaBaseFS.ReadFile("valuesSchemaBase.json")
	if err != nil {
		return nil, fmt.Errorf("read valuesSchemaBase.json: %w", err)
	}
	var schema map[string]interface{}
	if err := json.Unmarshal(data, &schema); err != nil {
		return nil, fmt.Errorf("parse valuesSchemaBase.json: %w", err)
	}
	return schema, nil
}

// setResourcesProps fills in the "resources" and "defaults.resources"
// properties left empty in valuesSchemaBase.json with the per-kind schemas
// built from resources.yaml.
func setResourcesProps(schema map[string]interface{}, resourcesProps, defaultsResourcesProps map[string]interface{}) error {
	properties, ok := schema["properties"].(map[string]interface{})
	if !ok {
		return fmt.Errorf("valuesSchemaBase.json: missing top-level \"properties\"")
	}

	resources, ok := properties["resources"].(map[string]interface{})
	if !ok {
		return fmt.Errorf("valuesSchemaBase.json: missing \"properties.resources\"")
	}
	resources["properties"] = resourcesProps

	defaults, ok := properties["defaults"].(map[string]interface{})
	if !ok {
		return fmt.Errorf("valuesSchemaBase.json: missing \"properties.defaults\"")
	}
	defaultsProperties, ok := defaults["properties"].(map[string]interface{})
	if !ok {
		return fmt.Errorf("valuesSchemaBase.json: missing \"properties.defaults.properties\"")
	}
	defaultsResources, ok := defaultsProperties["resources"].(map[string]interface{})
	if !ok {
		return fmt.Errorf("valuesSchemaBase.json: missing \"properties.defaults.properties.resources\"")
	}
	defaultsResources["properties"] = defaultsResourcesProps

	return nil
}

// generateValuesSchema writes schema/values.schema.json: a JSON Schema
// describing .Values.resources.<kind>.<id> and .Values.defaults.resources.<kind>.
// Each kind's instance schema lives in schema/resources/<name>.json (written
// by fetchAndTransformSchema) and has no top-level "required" (see
// stripRequiredTransform), so both .Values.resources.<kind> and
// .Values.defaults.resources.<kind> can safely $ref that same single file -
// required-field validation on the merged resource is instead generated
// into templates/_generated.tpl (see resources.requireFields).
//
// This file is kept around (alongside the chart-root values.schema.json
// written by generateChartValuesSchema) purely for editor/IDE tooling (see
// the "$schema" comment at the top of ci/*-values.yaml files), since editors
// resolving "$ref" against a sibling file is simpler to read/diff than the
// fully inlined chart-root schema.
func generateValuesSchema(dir string, entries []resource) error {
	schema, err := buildValuesSchema(entries, func(name string) (interface{}, error) {
		return map[string]interface{}{"$ref": "./resources/" + name + ".json"}, nil
	})
	if err != nil {
		return err
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

// generateChartValuesSchema writes values.schema.json at the chart root:
// the same JSON Schema as generateValuesSchema, except each kind's instance
// schema is inlined (under a top-level "$defs" section, referenced via a
// same-document "$ref": "#/$defs/<kind>") rather than referenced via a
// cross-file "$ref". This is the file Helm auto-loads and validates
// .Values against for this chart (Helm only auto-validates that exact
// path, and doesn't resolve "$ref" against sibling files the way
// schema/values.schema.json relies on for editor tooling), so it must be
// fully self-contained.
//
// Each kind's schema is stored once under "$defs" and referenced from both
// .Values.resources.<kind>.<id> and .Values.defaults.resources.<kind>,
// rather than inlined twice, and the result is marshaled compactly
// (without indentation): Helm rejects any single chart file over 5MiB, and
// this chart's combined kind schemas (dominated by a handful of large CRDs)
// are large enough that both of these are needed to stay under that limit.
func generateChartValuesSchema(dir string, entries []resource) error {
	schemaDir := filepath.Join(dir, "schema", "resources")

	defs := map[string]interface{}{}
	resourcesProps := map[string]interface{}{}
	defaultsResourcesProps := map[string]interface{}{}

	for _, e := range entries {
		data, err := os.ReadFile(filepath.Join(schemaDir, e.Name+".json"))
		if err != nil {
			return fmt.Errorf("read %s.json: %w", e.Name, err)
		}
		var inlined map[string]interface{}
		if err := json.Unmarshal(data, &inlined); err != nil {
			return fmt.Errorf("parse %s.json: %w", e.Name, err)
		}
		defs[e.Name] = inlined

		ref := map[string]interface{}{"$ref": "#/$defs/" + e.Name}
		resourcesProps[e.Name] = map[string]interface{}{
			"type":                 "object",
			"description":          fmt.Sprintf("%s instances, keyed by id.", e.Kind),
			"additionalProperties": ref,
		}
		defaultsResourcesProps[e.Name] = map[string]interface{}{"$ref": "#/$defs/" + e.Name}
	}

	schema, err := loadValuesSchemaBase()
	if err != nil {
		return err
	}
	schema["$defs"] = defs
	if err := setResourcesProps(schema, resourcesProps, defaultsResourcesProps); err != nil {
		return err
	}

	out, err := json.Marshal(schema)
	if err != nil {
		return fmt.Errorf("marshal values.schema.json: %w", err)
	}
	out = append(out, '\n')

	dest := filepath.Join(dir, "values.schema.json")
	fmt.Printf("generating %s\n", dest)
	return os.WriteFile(dest, out, 0o644)
}

// buildValuesSchema builds the JSON Schema used by generateValuesSchema,
// describing .Values.resources.<kind>.<id> and
// .Values.defaults.resources.<kind>. resolve returns the "$ref" to use for
// a given kind's instance schema, and is called twice per kind (once for
// .Values.resources.<kind>'s additionalProperties, once for
// .Values.defaults.resources.<kind>) so each call site gets its own,
// independent value.
func buildValuesSchema(entries []resource, resolve func(name string) (interface{}, error)) (map[string]interface{}, error) {
	resourcesProps := map[string]interface{}{}
	defaultsResourcesProps := map[string]interface{}{}

	for _, e := range entries {
		instanceSchema, err := resolve(e.Name)
		if err != nil {
			return nil, err
		}
		resourcesProps[e.Name] = map[string]interface{}{
			"type":                 "object",
			"description":          fmt.Sprintf("%s instances, keyed by id.", e.Kind),
			"additionalProperties": instanceSchema,
		}

		defaultsSchema, err := resolve(e.Name)
		if err != nil {
			return nil, err
		}
		defaultsResourcesProps[e.Name] = defaultsSchema
	}

	schema, err := loadValuesSchemaBase()
	if err != nil {
		return nil, err
	}
	if err := setResourcesProps(schema, resourcesProps, defaultsResourcesProps); err != nil {
		return nil, err
	}

	return schema, nil
}
