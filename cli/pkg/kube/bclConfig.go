package kube

import (
	"fmt"
	"os"
	"path/filepath"
	"reflect"
	"strings"

	"github.com/becloudless/becloudless/pkg/git"
	"github.com/n0rad/go-erlog/data"
	"github.com/n0rad/go-erlog/errs"
	"gopkg.in/yaml.v3"
)

// TODO generate from schema
type BclConfig struct {
	Global struct {
		Name   string `yaml:"name"`
		Domain string `yaml:"domain"`
	} `yaml:"global"`
}

func (bcl BclConfig) ToEnv() map[string]string {
	res := make(map[string]string)
	toEnvRec(reflect.ValueOf(bcl), "BCL", res)
	return res
}

func toEnvRec(v reflect.Value, parentKey string, envMap map[string]string) {
	if !v.IsValid() {
		return
	}
	// Dereference pointers/interfaces
	for v.Kind() == reflect.Pointer || v.Kind() == reflect.Interface {
		if v.IsNil() {
			return
		}
		v = v.Elem()
	}

	switch v.Kind() {
	case reflect.Map:
		iter := v.MapRange()
		for iter.Next() {
			keyVal := iter.Key()
			if keyVal.Kind() != reflect.String {
				continue
			}
			toEnvRec(iter.Value(), parentKey+"_"+strings.ToUpper(strings.ReplaceAll(keyVal.String(), "-", "_")), envMap)
		}
	case reflect.Slice, reflect.Array:
		for i := 0; i < v.Len(); i++ {
			idxKey := fmt.Sprintf("%s_%d", parentKey, i)
			toEnvRec(v.Index(i), idxKey, envMap)
		}
	case reflect.Struct:
		t := v.Type()
		for i := 0; i < v.NumField(); i++ {
			field := t.Field(i)
			if field.PkgPath != "" { // unexported
				continue
			}
			toEnvRec(v.Field(i), parentKey+"_"+strings.ToUpper(strings.ReplaceAll(field.Name, "-", "_")), envMap)
		}
	default:
		envMap[parentKey] = fmt.Sprintf("%v", v.Interface())
	}
}

func GetBclConfig(gitRepo *git.Repository) (BclConfig, error) {
	bclConfig := BclConfig{}

	const configGlobalPath = "config/global.yaml"
	content, err := os.ReadFile(filepath.Join(gitRepo.Root, configGlobalPath))
	if err != nil {
		return bclConfig, errs.WithEF(err, data.WithField("path", configGlobalPath), "Failed to read BCL global config")
	}

	if err := yaml.Unmarshal(content, &bclConfig); err != nil {
		return bclConfig, errs.WithEF(err, data.WithField("path", configGlobalPath), "Failed to unmarshal BCL global config")
	}

	return bclConfig, nil
}
