package generate

import (
	"fmt"
	"os"
	"path/filepath"
)

// Run drives the full build pipeline: parse resources.yaml, fetch and transform
// each kind's upstream k8s JSON schema, then generate the chart's templates
// and aggregate values schemas (both the $ref-based schema/values.schema.json
// and the inlined, chart-root values.schema.json Helm actually validates
// against) from the result.
func Run() error {
	dir, err := os.Getwd()
	if err != nil {
		return fmt.Errorf("getwd: %w", err)
	}

	yamlPath := filepath.Join(dir, "resources.yaml")
	entries, err := parseResources(yamlPath)
	if err != nil {
		return fmt.Errorf("parse %s: %w", yamlPath, err)
	}
	if len(entries) == 0 {
		return fmt.Errorf("no entries found in %s", yamlPath)
	}

	if err := fetchSchemas(dir, entries); err != nil {
		return err
	}

	if err := generateTemplate(dir, entries); err != nil {
		return err
	}

	if err := generateValuesSchema(dir, entries); err != nil {
		return err
	}

	if err := generateChartValuesSchema(dir, entries); err != nil {
		return err
	}

	return nil
}
