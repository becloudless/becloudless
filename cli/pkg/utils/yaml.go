package utils

import (
	"github.com/n0rad/go-erlog/errs"
	"gopkg.in/yaml.v3"
	"os"
)

func YamlMarshalToFile(filePath string, data any, perm os.FileMode) error {
	file, err := os.OpenFile(filePath, os.O_CREATE|os.O_TRUNC|os.O_WRONLY, perm)
	if err != nil {
		return errs.WithE(err, "Failed to open file to write yaml content")
	}
	defer file.Close()

	encoder := yaml.NewEncoder(file)
	encoder.SetIndent(2)

	if err := encoder.Encode(data); err != nil {
		return errs.WithE(err, "Failed to marshal data")
	}
	return nil
}
