package generate

import (
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"time"

	"resourceschart/generate/mutation"
)

func fetchSchemas(dir string, entries []resource) error {
	schemaDir := filepath.Join(dir, "schema", "resources")
	if err := os.MkdirAll(schemaDir, 0o755); err != nil {
		return fmt.Errorf("mkdir %s: %w", schemaDir, err)
	}

	client := &http.Client{Timeout: 30 * time.Second}

	var failed []string
	for i := range entries {
		e := &entries[i]
		if e.URL == "" {
			continue
		}
		dest := filepath.Join(schemaDir, e.Name+".json")
		fmt.Printf("fetching %s -> %s\n", e.URL, dest)
		if err := fetchAndMutateSchema(client, e, dest); err != nil {
			fmt.Fprintf(os.Stderr, "  failed: %v\n", err)
			failed = append(failed, e.Name)
			continue
		}
	}

	if len(failed) > 0 {
		return fmt.Errorf("failed to fetch schemas: %s", strings.Join(failed, ", "))
	}
	return nil
}

func fetchAndMutateSchema(client *http.Client, e *resource, dest string) error {
	var kindSchema map[string]any
	switch {
	case e.CRDVersion != "":
		schema, err := fetchCRDManifestSchema(client, e.URL, e.CRDVersion, e.Kind)
		if err != nil {
			return err
		}
		kindSchema = schema
	case e.Component != "":
		schema, err := fetchOpenAPIV3Schema(client, e.URL, e.Component)
		if err != nil {
			return err
		}
		kindSchema = schema
	default:
		resp, err := client.Get(e.URL)
		if err != nil {
			return err
		}
		defer resp.Body.Close()

		if resp.StatusCode != http.StatusOK {
			return fmt.Errorf("unexpected status %s", resp.Status)
		}

		body, err := io.ReadAll(resp.Body)
		if err != nil {
			return err
		}

		if err := json.Unmarshal(body, &kindSchema); err != nil {
			return fmt.Errorf("parse fetched schema: %w", err)
		}
	}

	pipeline := mutation.Pipeline(
		mutation.ExtractContent{ContentIsOutOfSpec: e.Mutations.ContentIsOutOfSpec, KindName: e.Name},
		e.Mutations.ArraysToMaps,
		e.Mutations.StringifyFields,
	)
	result, err := mutation.MutateSchema(pipeline, kindSchema)
	if err != nil {
		return err
	}
	e.templateArgs = result.TemplateArgs

	out, err := json.MarshalIndent(result.Schema, "", "  ")
	if err != nil {
		return fmt.Errorf("marshal instance schema: %w", err)
	}
	out = append(out, '\n')

	return os.WriteFile(dest, out, 0o644)
}
