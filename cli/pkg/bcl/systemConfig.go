package bcl

import (
	"os"

	"github.com/goccy/go-yaml"
	"github.com/n0rad/go-erlog/data"
	"github.com/n0rad/go-erlog/errs"
)

const PathSystemConfig = "/etc/bcl/config.yaml"

type SystemConfig struct {
	Repository string `yaml:"repository,omitempty"`
}

func LoadSystemConfig() (*SystemConfig, error) {
	if stat, err := os.Stat(PathSystemConfig); os.IsNotExist(err) {
		return nil, nil
	} else if err != nil {
		return nil, errs.WithEF(err, data.WithField("path", PathSystemConfig), "Failed to read system config file")
	} else if stat.IsDir() {
		return nil, errs.WithF(data.WithField("path", PathSystemConfig), "Folder found on system config location")
	}

	bytes, err := os.ReadFile(PathSystemConfig)
	if err != nil {
		return nil, errs.WithEF(err, data.WithField("path", PathSystemConfig), "Failed to read system config file")
	}

	var config SystemConfig
	if err := yaml.Unmarshal(bytes, &config); err != nil {
		return nil, errs.WithEF(err, data.WithField("content", string(bytes)).WithField("path", PathSystemConfig), "Failed to parse system config file")
	}
	return &config, nil
}

func LoadSystemConfigFromBytes(bytes []byte) (*SystemConfig, error) {
	var config SystemConfig
	if err := yaml.Unmarshal(bytes, &config); err != nil {
		return nil, errs.WithEF(err, data.WithField("content", string(bytes)), "Failed to parse system config file")
	}
	return &config, nil
}
