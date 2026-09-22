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

	"resourceschart/generate/transform"
)

// fetchSchemas fetches and transforms the upstream k8s JSON schema for every
// resource that declares a url, writing the result to
// schema/resources/<name>.json. Entries without a url are skipped.
func fetchSchemas(dir string, entries []resource) error {
	schemaDir := filepath.Join(dir, "schema", "resources")
	if err := os.MkdirAll(schemaDir, 0o755); err != nil {
		return fmt.Errorf("mkdir %s: %w", schemaDir, err)
	}

	client := &http.Client{Timeout: 30 * time.Second}

	var failed []string
	for i := range entries {
		e := &entries[i]
		if e.url == "" {
			continue
		}
		dest := filepath.Join(schemaDir, e.name+".json")
		fmt.Printf("fetching %s -> %s\n", e.url, dest)
		if err := fetchAndTransformSchema(client, e, dest); err != nil {
			fmt.Fprintf(os.Stderr, "  failed: %v\n", err)
			failed = append(failed, e.name)
			continue
		}
	}

	if len(failed) > 0 {
		return fmt.Errorf("failed to fetch schemas: %s", strings.Join(failed, ", "))
	}
	return nil
}

// fetchAndTransformSchema fetches a kind's full k8s JSON schema from e.url
// and runs it through the transformer pipeline (see the transform package)
// to produce the instance schema used for .Values.resources.<name>.<id>
// (and shared, as-is, by .Values.defaults.resources.<name>), writing the
// result to dest. schema/resources/<name>.json therefore holds the
// ready-to-use instance schema, not the raw upstream k8s schema.
// Transformers may also populate e.required as a side effect (see
// transform.StripRequired).
//
// If e.crdVersion is set, e.url is instead treated as a CRD manifest (YAML)
// and the schema is extracted from it (see fetchCRDManifestSchema) rather
// than parsed directly as JSON. Otherwise, if e.component is set, e.url is
// treated as a Kubernetes OpenAPI v3 spec document and the schema is
// extracted (with $ref pointers resolved) from it (see
// fetchOpenAPIV3Schema).
func fetchAndTransformSchema(client *http.Client, e *resource, dest string) error {
	var kindSchema map[string]interface{}
	switch {
	case e.crdVersion != "":
		schema, err := fetchCRDManifestSchema(client, e.url, e.crdVersion, e.kind)
		if err != nil {
			return err
		}
		kindSchema = schema
	case e.component != "":
		schema, err := fetchOpenAPIV3Schema(client, e.url, e.component)
		if err != nil {
			return err
		}
		kindSchema = schema
	default:
		resp, err := client.Get(e.url)
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

	te := &transform.Entry{Name: e.name, ContentIsSpec: e.contentIsSpec, TransformerConfig: e.transformerConfig}
	instance, err := transform.Apply(transform.DefaultTransformers, kindSchema, te)
	if err != nil {
		return err
	}
	e.required = te.Required

	out, err := json.MarshalIndent(instance, "", "  ")
	if err != nil {
		return fmt.Errorf("marshal instance schema: %w", err)
	}
	out = append(out, '\n')

	return os.WriteFile(dest, out, 0o644)
}
