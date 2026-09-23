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

// fetchAndMutateSchema fetches a kind's full k8s JSON schema from e.URL
// and runs it through the mutation pipeline (see the mutation package)
// to produce the instance schema used for .Values.resources.<name>.<id>
// (and shared, as-is, by .Values.defaults.resources.<name>), writing the
// result to dest. schema/resources/<name>.json therefore holds the
// ready-to-use instance schema, not the raw upstream k8s schema.
// Mutations may also populate e.templateArgs as a side effect (see
// mutation.Entry.AddTemplateArg).
//
// If e.CRDVersion is set, e.URL is instead treated as a CRD manifest (YAML)
// and the schema is extracted from it (see fetchCRDManifestSchema) rather
// than parsed directly as JSON. Otherwise, if e.Component is set, e.URL is
// treated as a Kubernetes OpenAPI v3 spec document and the schema is
// extracted (with $ref pointers resolved) from it (see
// fetchOpenAPIV3Schema).
func fetchAndMutateSchema(client *http.Client, e *resource, dest string) error {
	var kindSchema map[string]interface{}
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

	te := &mutation.Entry{Name: e.Name, MutationConfig: e.mutationConfig}
	instance, err := mutation.Apply(mutation.DefaultMutations, kindSchema, te)
	if err != nil {
		return err
	}
	e.templateArgs = te.TemplateArgs

	out, err := json.MarshalIndent(instance, "", "  ")
	if err != nil {
		return fmt.Errorf("marshal instance schema: %w", err)
	}
	out = append(out, '\n')

	return os.WriteFile(dest, out, 0o644)
}
