package generate

import (
	"encoding/json"
	"fmt"
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
		url := e.sourceURL()
		if url == "" {
			continue
		}
		dest := filepath.Join(schemaDir, e.Name+".json")
		fmt.Printf("fetching %s -> %s\n", url, dest)
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

// sourceURL returns the URL to fetch the schema from, or "" if the
// resource has no source configured.
func (e *resource) sourceURL() string {
	switch {
	case e.SourceCRD != nil:
		return e.SourceCRD.URL
	case e.SourceOpenAPI != nil:
		return e.SourceOpenAPI.URL
	default:
		return ""
	}
}

func fetchAndMutateSchema(client *http.Client, e *resource, dest string) error {
	var kindSchema map[string]any
	switch {
	case e.SourceCRD != nil:
		schema, err := fetchCRDManifestSchema(client, e.SourceCRD.URL, e.SourceCRD.CRDVersion, e.Kind)
		if err != nil {
			return err
		}
		kindSchema = schema
	case e.SourceOpenAPI != nil:
		schema, err := fetchOpenAPIV3Schema(client, e.SourceOpenAPI.URL, e.SourceOpenAPI.Component)
		if err != nil {
			return err
		}
		kindSchema = schema
	default:
		return fmt.Errorf("%s: must set either sourceOpenAPI or sourceCRD", e.Name)
	}

	extractContent := mutation.ExtractContent{}
	if e.Mutations.ExtractContent != nil {
		extractContent = *e.Mutations.ExtractContent
	}
	extractContent.KindName = e.Name

	pipeline := mutation.Pipeline(
		extractContent,
		e.Mutations.ArraysToMaps,
		e.Mutations.StringifyFields,
	)
	result, err := mutation.MutateSchema(pipeline, kindSchema)
	if err != nil {
		return err
	}
	e.helmTemplateRenderArgs = result.TemplateArgs

	out, err := json.MarshalIndent(result.Schema, "", "  ")
	if err != nil {
		return fmt.Errorf("marshal instance schema: %w", err)
	}
	out = append(out, '\n')

	return os.WriteFile(dest, out, 0o644)
}
