package main

import (
	"fmt"
	"os"
	"path/filepath"
)

// run drives the full build pipeline: parse CRDs.yaml, fetch and transform
// each kind's upstream k8s JSON schema, then generate the chart's templates
// and aggregate values schema from the result.
func run() error {
	dir, err := os.Getwd()
	if err != nil {
		return fmt.Errorf("getwd: %w", err)
	}

	yamlPath := filepath.Join(dir, "CRDs.yaml")
	entries, err := parseCRDs(yamlPath)
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

	return nil
}
