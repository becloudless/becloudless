package nixos

import (
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"slices"
	"strings"

	"github.com/becloudless/becloudless/pkg/system/runner"
	"github.com/n0rad/go-erlog/data"
	"github.com/n0rad/go-erlog/errs"
)

const intelCommon = "intel"
const intelKernelModule = "kvm-intel"

var generatedModuleListPattern = regexp.MustCompile(`(?m)^\s*(boot\.initrd\.availableKernelModules|boot\.initrd\.kernelModules|boot\.kernelModules)\s*=\s*\[([^\]]*)\];`)
var generatedHostPlatformPattern = regexp.MustCompile(`nixpkgs\.hostPlatform\s*=\s*lib\.mkDefault\s*"([^"]+)"`)
var quotedValuePattern = regexp.MustCompile(`"([^"]+)"`)
var nonNamePattern = regexp.MustCompile(`[^a-z0-9]+`)

// HardwareProfile is what a hardware module sets for a device
type HardwareProfile struct {
	Commons                      []string
	InitrdAvailableKernelModules []string
	InitrdKernelModules          []string
	KernelModules                []string
	HostPlatform                 string
}

type AddHardwareOptions struct {
	InfraDirectory string
	Name           string
	Profile        HardwareProfile
}

// AddHardware returns the path of the created default.nix, it never overwrites an existing hardware
func AddHardware(options AddHardwareOptions) (string, error) {
	if !namePattern.MatchString(options.Name) {
		return "", errs.WithF(data.WithField("name", options.Name), "Hardware name must be lowercase letters, digits and dashes")
	}

	hardwareDirectory := filepath.Join(options.InfraDirectory, "nixos", "modules", "nixos", "hardware", options.Name)
	hardwareField := data.WithField("directory", hardwareDirectory)
	hardwareFile := filepath.Join(hardwareDirectory, "default.nix")

	if _, err := os.Stat(hardwareFile); err == nil {
		return "", errs.WithF(hardwareField, "Hardware already exists")
	} else if !os.IsNotExist(err) {
		return "", errs.WithEF(err, hardwareField, "Failed to check hardware file")
	}

	if err := os.MkdirAll(hardwareDirectory, 0755); err != nil {
		return "", errs.WithEF(err, hardwareField, "Failed to create hardware directory")
	}
	if err := os.WriteFile(hardwareFile, []byte(renderHardware(options)), 0644); err != nil {
		return "", errs.WithEF(err, hardwareField, "Failed to write hardware file")
	}
	return hardwareFile, nil
}

func renderHardware(options AddHardwareOptions) string {
	profile := options.Profile
	name := nixString(options.Name)

	var content strings.Builder
	content.WriteString("{ config, lib, ... }:\n\n{\n  config = lib.mkMerge [\n")
	fmt.Fprintf(&content, "    { bcl.hardware.knownDevices = [ %s ]; }\n", name)
	fmt.Fprintf(&content, "    (lib.mkIf (config.bcl.hardware.device == %s) {\n", name)
	if len(profile.Commons) > 0 {
		fmt.Fprintf(&content, "      bcl.hardware.commons = %s;\n", nixStringList(profile.Commons))
	}
	if profile.HostPlatform != "" {
		fmt.Fprintf(&content, "      nixpkgs.hostPlatform = lib.mkDefault %s;\n", nixString(profile.HostPlatform))
	}
	if len(profile.InitrdAvailableKernelModules) > 0 {
		fmt.Fprintf(&content, "      boot.initrd.availableKernelModules = %s;\n", nixStringList(profile.InitrdAvailableKernelModules))
	}
	if len(profile.InitrdKernelModules) > 0 {
		fmt.Fprintf(&content, "      boot.initrd.kernelModules = %s;\n", nixStringList(profile.InitrdKernelModules))
	}
	if len(profile.KernelModules) > 0 {
		fmt.Fprintf(&content, "      boot.kernelModules = %s;\n", nixStringList(profile.KernelModules))
	}
	content.WriteString("    })\n  ];\n}\n")
	return content.String()
}

// DetectHardwareProfile deduces the profile from the output of nixos-generate-config run on the host
func DetectHardwareProfile(run runner.Runner) (HardwareProfile, error) {
	generatedConfig, err := run.ExecCmdGetStdout("nixos-generate-config", "--no-filesystems", "--show-hardware-config")
	if err != nil {
		return HardwareProfile{}, errs.WithE(err, "Failed to generate the hardware configuration of the host, is it running nixos or the installer?")
	}
	return ParseGeneratedHardwareConfig(generatedConfig), nil
}

// DetectHardwareName deduces a hardware name from the product name of the host
func DetectHardwareName(run runner.Runner) (string, error) {
	productName, err := run.ExecCmdGetStdout("cat", "/sys/devices/virtual/dmi/id/product_name")
	if err != nil {
		return "", errs.WithE(err, "Failed to read the product name of the host")
	}
	name := strings.Trim(nonNamePattern.ReplaceAllString(strings.ToLower(productName), "-"), "-")
	if name == "" {
		return "", errs.With("The host does not expose a product name, a hardware name is required")
	}
	return name, nil
}

func ParseGeneratedHardwareConfig(generatedConfig string) HardwareProfile {
	profile := HardwareProfile{}

	for _, match := range generatedModuleListPattern.FindAllStringSubmatch(generatedConfig, -1) {
		modules := []string{}
		for _, moduleMatch := range quotedValuePattern.FindAllStringSubmatch(match[2], -1) {
			modules = append(modules, moduleMatch[1])
		}
		switch match[1] {
		case "boot.initrd.availableKernelModules":
			profile.InitrdAvailableKernelModules = modules
		case "boot.initrd.kernelModules":
			profile.InitrdKernelModules = modules
		case "boot.kernelModules":
			profile.KernelModules = modules
		}
	}

	if match := generatedHostPlatformPattern.FindStringSubmatch(generatedConfig); match != nil {
		profile.HostPlatform = match[1]
	}

	// the intel common already sets the kvm module and the host platform
	if slices.Contains(profile.KernelModules, intelKernelModule) {
		profile.Commons = append(profile.Commons, intelCommon)
		profile.KernelModules = slices.DeleteFunc(profile.KernelModules, func(module string) bool { return module == intelKernelModule })
		profile.HostPlatform = ""
	}
	return profile
}
