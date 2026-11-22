package repository

import (
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"strings"

	"github.com/n0rad/go-erlog/data"
	"github.com/n0rad/go-erlog/errs"
)

const DefaultNixosSystemArchitecture = "x86_64-linux"

var nixosNamePattern = regexp.MustCompile(`^[a-z0-9]([a-z0-9-]*[a-z0-9])?$`)

type AddNixosSystemOptions struct {
	InfraDirectory  string
	Name            string
	Architecture    string
	Group           string
	Hardware        string
	Devices         []string
	MotherboardUuid string
	NetworkMacs     []string
}

// AddNixosSystem returns the path of the created default.nix, it never overwrites an existing system
func AddNixosSystem(options AddNixosSystemOptions) (string, error) {
	if !nixosNamePattern.MatchString(options.Name) {
		return "", errs.WithF(data.WithField("name", options.Name), "System name must be lowercase letters, digits and dashes")
	}
	if options.Group == "" {
		return "", errs.With("System group is required")
	}

	architecture := options.Architecture
	if architecture == "" {
		architecture = DefaultNixosSystemArchitecture
	}

	systemDirectory := filepath.Join(options.InfraDirectory, "nixos", "systems", architecture, options.Name)
	systemField := data.WithField("directory", systemDirectory)
	systemFile := filepath.Join(systemDirectory, "default.nix")

	if _, err := os.Stat(systemFile); err == nil {
		return "", errs.WithF(systemField, "System already exists")
	} else if !os.IsNotExist(err) {
		return "", errs.WithEF(err, systemField, "Failed to check system file")
	}

	if err := os.MkdirAll(systemDirectory, 0755); err != nil {
		return "", errs.WithEF(err, systemField, "Failed to create system directory")
	}
	if err := os.WriteFile(systemFile, []byte(renderNixosSystem(options)), 0644); err != nil {
		return "", errs.WithEF(err, systemField, "Failed to write system file")
	}
	return systemFile, nil
}

func renderNixosSystem(options AddNixosSystemOptions) string {
	var content strings.Builder
	content.WriteString("{\n  bcl.system = {\n")
	if options.Hardware != "" {
		fmt.Fprintf(&content, "    hardware = %s;\n", nixString(options.Hardware))
	}
	fmt.Fprintf(&content, "    group = %s;\n", nixString(options.Group))
	if len(options.Devices) > 0 {
		fmt.Fprintf(&content, "    devices = %s;\n", nixStringList(options.Devices))
	}
	if options.MotherboardUuid != "" {
		fmt.Fprintf(&content, "    id.motherboardUuid = %s;\n", nixString(options.MotherboardUuid))
	}
	if len(options.NetworkMacs) > 0 {
		fmt.Fprintf(&content, "    id.networkMacs = %s;\n", nixStringList(options.NetworkMacs))
	}
	content.WriteString("  };\n}\n")
	return content.String()
}

func nixString(value string) string {
	escaped := strings.NewReplacer(`\`, `\\`, `"`, `\"`, "${", `\${`).Replace(value)
	return `"` + escaped + `"`
}

func nixStringList(values []string) string {
	quotedValues := make([]string, len(values))
	for i, value := range values {
		quotedValues[i] = nixString(value)
	}
	return "[ " + strings.Join(quotedValues, " ") + " ]"
}
