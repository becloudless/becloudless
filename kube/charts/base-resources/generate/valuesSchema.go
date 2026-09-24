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


func loadValuesSchemaBase() (map[string]any, error) {
	data, err := valuesSchemaBaseFS.ReadFile("valuesSchemaBase.json")
	if err != nil {
		return nil, fmt.Errorf("read valuesSchemaBase.json: %w", err)
	}
	var schema map[string]any
	if err := json.Unmarshal(data, &schema); err != nil {
		return nil, fmt.Errorf("parse valuesSchemaBase.json: %w", err)
	}
	return schema, nil
}

func setResourcesProps(schema map[string]any, resourcesProps, defaultsResourcesProps map[string]any) error {
	properties, ok := schema["properties"].(map[string]any)
	if !ok {
		return fmt.Errorf("valuesSchemaBase.json: missing top-level \"properties\"")
	}

	resources, ok := properties["resources"].(map[string]any)
	if !ok {
		return fmt.Errorf("valuesSchemaBase.json: missing \"properties.resources\"")
	}
	resources["properties"] = resourcesProps

	defaults, ok := properties["defaults"].(map[string]any)
	if !ok {
		return fmt.Errorf("valuesSchemaBase.json: missing \"properties.defaults\"")
	}
	defaultsProperties, ok := defaults["properties"].(map[string]any)
	if !ok {
		return fmt.Errorf("valuesSchemaBase.json: missing \"properties.defaults.properties\"")
	}
	defaultsResources, ok := defaultsProperties["resources"].(map[string]any)
	if !ok {
		return fmt.Errorf("valuesSchemaBase.json: missing \"properties.defaults.properties.resources\"")
	}
	defaultsResources["properties"] = defaultsResourcesProps

	return nil
}

func generateValuesSchema(dir string, entries []resource) error {
	schema, err := buildValuesSchema(entries, func(name string) (any, error) {
		return map[string]any{"$ref": "./resources/" + name + ".json"}, nil
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

func generateChartValuesSchema(dir string, entries []resource) error {
	schemaDir := filepath.Join(dir, "schema", "resources")

	defs := map[string]any{}
	resourcesProps := map[string]any{}
	defaultsResourcesProps := map[string]any{}

	for _, e := range entries {
		data, err := os.ReadFile(filepath.Join(schemaDir, e.Name+".json"))
		if err != nil {
			return fmt.Errorf("read %s.json: %w", e.Name, err)
		}
		var inlined map[string]any
		if err := json.Unmarshal(data, &inlined); err != nil {
			return fmt.Errorf("parse %s.json: %w", e.Name, err)
		}
		defs[e.Name] = inlined

		ref := map[string]any{"$ref": "#/$defs/" + e.Name}
		resourcesProps[e.Name] = map[string]any{
			"type":                 "object",
			"description":          fmt.Sprintf("%s instances, keyed by id.", e.Kind),
			"additionalProperties": ref,
		}
		defaultsResourcesProps[e.Name] = map[string]any{"$ref": "#/$defs/" + e.Name}
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

func buildValuesSchema(entries []resource, resolve func(name string) (any, error)) (map[string]any, error) {
	resourcesProps := map[string]any{}
	defaultsResourcesProps := map[string]any{}

	for _, e := range entries {
		instanceSchema, err := resolve(e.Name)
		if err != nil {
			return nil, err
		}
		resourcesProps[e.Name] = map[string]any{
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
