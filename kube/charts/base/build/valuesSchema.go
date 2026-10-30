package build

import (
	"embed"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strings"
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

// podSchemaPointer and containerSchemaPointer are where the schema of a pod spec and of a container are in the schema of the
// deployments: the containers are a map keyed by id once the arrays are converted. All the kinds with a pod template share the
// same schemas.
const (
	podSchemaPointer       = "/properties/template/properties/spec"
	containerSchemaPointer = podSchemaPointer + "/properties/containers/additionalProperties"
)

func defaultsPodSchemas(deploymentsRef string) (pod, container map[string]any) {
	ref := func(pointer string) string {
		if strings.Contains(deploymentsRef, "#") {
			return deploymentsRef + pointer
		}
		return deploymentsRef + "#" + pointer // a file reference, the pointer is its fragment
	}
	pod = map[string]any{
		"description": "Defaults of the pod spec of the deployments, statefulSets, daemonSets, jobs and cronJobs. The fields set by the resource win, even `false` or `0`.",
		"$ref":        ref(podSchemaPointer),
	}
	container = map[string]any{
		"description": "Defaults of every container and initContainer of the deployments, statefulSets, daemonSets, jobs and cronJobs. The fields set by a container win, even `false` or `0`.",
		"$ref":        ref(containerSchemaPointer),
	}
	return pod, container
}

func setResourcesProps(schema map[string]any, resourcesProps, defaultsResourcesProps map[string]any, deploymentsRef string) error {
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
	defaultsProperties["pod"], defaultsProperties["container"] = defaultsPodSchemas(deploymentsRef)

	return nil
}

func generateValuesSchema(dir string, entries []resource) error {
	schema, err := buildValuesSchema(entries, func(name string) (any, error) {
		return map[string]any{"$ref": "./resources/" + name + ".json"}, nil
	}, "./resources/deployments.json")
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
	docs := make([]schemaDoc, 0, len(entries))

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
		docs = append(docs, schemaDoc{name: e.Name, root: inlined})

		ref := map[string]any{"$ref": "#/$defs/" + e.Name}
		resourcesProps[e.Name] = map[string]any{
			"type":                 "object",
			"description":          fmt.Sprintf("%s instances, keyed by id.", e.Kind),
			"additionalProperties": ref,
		}
		defaultsResourcesProps[e.Name] = map[string]any{"$ref": "#/$defs/" + e.Name}
	}

	// the schema is inlined: the subschemas shared by the kinds, the pod spec of the workloads for most, are defined once
	location := func(_, to string, tokens []string) string {
		return "#/$defs/" + to + pointerOf(tokens)
	}
	if err := optimizeSchemas(orderDocs(docs, "deployments"), location, workloadPointers()); err != nil {
		return err
	}

	schema, err := loadValuesSchemaBase()
	if err != nil {
		return err
	}
	schema["$defs"] = defs
	if err := setResourcesProps(schema, resourcesProps, defaultsResourcesProps, "#/$defs/deployments"); err != nil {
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

func buildValuesSchema(entries []resource, resolve func(name string) (any, error), deploymentsRef string) (map[string]any, error) {
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
	if err := setResourcesProps(schema, resourcesProps, defaultsResourcesProps, deploymentsRef); err != nil {
		return nil, err
	}

	return schema, nil
}
