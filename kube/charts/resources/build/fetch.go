package main

import (
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"time"
)

// fetchSchemas fetches and transforms the upstream k8s JSON schema for every
// entry that declares a url, writing the result to
// schema/resources/<name>.json. Entries without a url are skipped.
func fetchSchemas(dir string, entries []entry) error {
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
// and runs it through the transformer pipeline (see transform.go) to produce
// the instance schema used for .Values.resources.<name>.<id> (and shared,
// as-is, by .Values.defaultValues.<name>), writing the result to dest.
// schema/resources/<name>.json therefore holds the ready-to-use instance
// schema, not the raw upstream k8s schema. Transformers may also populate
// e.required as a side effect (see stripRequiredTransform).
func fetchAndTransformSchema(client *http.Client, e *entry, dest string) error {
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

	var kindSchema map[string]interface{}
	if err := json.Unmarshal(body, &kindSchema); err != nil {
		return fmt.Errorf("parse fetched schema: %w", err)
	}

	instance, err := applyTransformers(defaultTransformers, kindSchema, e)
	if err != nil {
		return err
	}

	out, err := json.MarshalIndent(instance, "", "  ")
	if err != nil {
		return fmt.Errorf("marshal instance schema: %w", err)
	}
	out = append(out, '\n')

	return os.WriteFile(dest, out, 0o644)
}
