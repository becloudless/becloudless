package generate

import (
	"bytes"
	"fmt"
	"io"
	"net/http"

	"gopkg.in/yaml.v3"
)

func fetchCRDManifestSchema(client *http.Client, url, crdVersion, kind string) (map[string]any, error) {
	resp, err := client.Get(url)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("unexpected status %s", resp.Status)
	}

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, err
	}

	decoder := yaml.NewDecoder(bytes.NewReader(body))
	for {
		var manifest map[string]any
		if err := decoder.Decode(&manifest); err != nil {
			if err == io.EOF {
				break
			}
			return nil, fmt.Errorf("parse CRD manifest: %w", err)
		}

		spec, _ := manifest["spec"].(map[string]any)
		if kind != "" {
			names, _ := spec["names"].(map[string]any)
			manifestKind, _ := names["kind"].(string)
			if manifestKind != kind {
				continue
			}
		}
		versions, _ := spec["versions"].([]any)
		for _, v := range versions {
			version, ok := v.(map[string]any)
			if !ok {
				continue
			}
			name, _ := version["name"].(string)
			if name != crdVersion {
				continue
			}
			schema, _ := version["schema"].(map[string]any)
			openAPISchema, _ := schema["openAPIV3Schema"].(map[string]any)
			if openAPISchema == nil {
				return nil, fmt.Errorf("CRD manifest %s: version %q has no spec.schema.openAPIV3Schema", url, crdVersion)
			}
			return openAPISchema, nil
		}
	}

	return nil, fmt.Errorf("CRD manifest %s: no document with kind %q and version %q found", url, kind, crdVersion)
}
