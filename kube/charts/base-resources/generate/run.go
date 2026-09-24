package generate

import (
	"fmt"
	"os"
	"path/filepath"
)

func Run() error {
	dir, err := os.Getwd()
	if err != nil {
		return fmt.Errorf("getwd: %w", err)
	}

	yamlPath := filepath.Join(dir, "resources.yaml")
	file, err := newResourcesFile(yamlPath)
	if err != nil {
		return fmt.Errorf("parse %s: %w", yamlPath, err)
	}
	resources := file.Resources
	if len(resources) == 0 {
		return fmt.Errorf("no entries found in %s", yamlPath)
	}

	if err := fetchSchemas(dir, resources); err != nil {
		return err
	}

	if err := generateTemplate(dir, resources); err != nil {
		return err
	}

	if err := generateValuesSchema(dir, resources); err != nil {
		return err
	}

	// TODO make schema validation faster
	// if err := generateChartValuesSchema(dir, entries); err != nil {
	// 	return err
	// }

	return nil
}
