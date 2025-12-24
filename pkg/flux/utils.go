package flux

import (
	"os"
	"path/filepath"

	"github.com/n0rad/go-erlog/data"
	"github.com/n0rad/go-erlog/errs"
	"gopkg.in/yaml.v3"
)

type NamespacedObjectKindReference struct {
	Kind      string `yaml:"kind"`
	Name      string `yaml:"name"`
	Namespace string `yaml:"namespace"`
}

func (n NamespacedObjectKindReference) DeduceNamespaceFromMetadata(metadata Metadata) NamespacedObjectKindReference {
	if n.Namespace == "" {
		n.Namespace = metadata.Namespace
	}
	return n
}

// Should be working with ociRepository and helmRepository
func GetRepositoryUrlAndRef(resourcesFolder string, objectReference NamespacedObjectKindReference) (string, string, error) {
	ref := ""
	url := ""
	found := false

	if err := filepath.WalkDir(resourcesFolder, func(path string, d os.DirEntry, err error) error {
		if err != nil {
			return err
		}
		if found {
			return filepath.SkipAll
		}

		if d.IsDir() {
			return nil
		}

		content, err := os.ReadFile(path)
		if err != nil {
			return errs.WithEF(err, data.WithField("path", path), "Failed to read file")
		}

		var repo struct {
			Kind     string `yaml:"kind"`
			Metadata struct {
				Name      string `yaml:"name"`
				Namespace string `yaml:"namespace"`
			} `yaml:"metadata"`
			Spec struct {
				Url string `yaml:"url"`
				Ref struct {
					Tag    string `yaml:"tag"`
					Branch string `yaml:"branch"`
				} `yaml:"ref"`
			} `yaml:"spec"`
		}
		if err := yaml.Unmarshal(content, &repo); err != nil {
			return errs.WithE(err, "Failed to parse flux OCIRepository")
		}

		if (repo.Kind == "OCIRepository" || repo.Kind == "HelmRepository") &&
			repo.Metadata.Name == objectReference.Name && repo.Metadata.Namespace == objectReference.Namespace {
			url = repo.Spec.Url
			if repo.Spec.Ref.Branch != "" {
				ref = repo.Spec.Ref.Branch
			} else if repo.Spec.Ref.Tag != "" {
				ref = repo.Spec.Ref.Tag
			}
			found = true
		}
		return nil
	}); err != nil {
		return "", "", errs.WithEF(err, data.WithField("folder", resourcesFolder), "Failed to walk resources folder to find repository")
	}
	if !found {
		return "", "", errs.WithF(data.WithField("name", objectReference.Name).WithField("namespace", objectReference.Namespace), "Repository not found")
	}
	return url, ref, nil
}

type Metadata struct {
	Name      string `yaml:"name"`
	Namespace string `yaml:"namespace"`
}

type Kustomization struct {
	Kind     string   `yaml:"kind"`
	Metadata Metadata `yaml:"metadata"`
	Spec     struct {
		SourceRef NamespacedObjectKindReference `yaml:"sourceRef"`
		Patches   []struct {
			Target struct {
				Kind      string `yaml:"kind"`
				Name      string `yaml:"name"`
				Namespace string `yaml:"namespace"`
			} `yaml:"target"`
			Patch string `yaml:"patch"`
		} `yaml:"patches"`
	} `yaml:"spec"`
}

type HelmRelease struct {
	Kind     string   `yaml:"kind"`
	Metadata Metadata `yaml:"metadata"`
	Spec     struct {
		Chart struct {
			Spec struct {
				Chart     string                        `yaml:"chart"`
				Version   string                        `yaml:"version"`
				SourceRef NamespacedObjectKindReference `yaml:"sourceRef"`
			} `yaml:"spec"`
		} `yaml:"chart"`
		Values map[string]any `yaml:"values"`
	} `yaml:"spec"`
}
