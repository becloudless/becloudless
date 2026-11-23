package nixos

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/becloudless/becloudless/pkg/system/runner"
	"github.com/stretchr/testify/assert"
)

const generatedIntelConfig = `# Do not modify this file!
{ config, lib, pkgs, modulesPath, ... }:

{
  imports =
    [ (modulesPath + "/installer/scan/not-detected.nix")
    ];

  boot.initrd.availableKernelModules = [ "xhci_pci" "ahci" "nvme" "sd_mod" ];
  boot.initrd.kernelModules = [ ];
  boot.kernelModules = [ "kvm-intel" ];
  boot.extraModulePackages = [ ];

  networking.useDHCP = lib.mkDefault true;
  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
}
`

const generatedAmdConfig = `{ config, lib, pkgs, modulesPath, ... }:
{
  boot.initrd.availableKernelModules = [ "nvme" "usbhid" ];
  boot.initrd.kernelModules = [ "r8169" ];
  boot.kernelModules = [ "kvm-amd" ];
  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
}
`

func TestParseGeneratedHardwareConfig_Intel(t *testing.T) {
	profile := ParseGeneratedHardwareConfig(generatedIntelConfig)

	assert.Equal(t, []string{"intel"}, profile.Commons)
	assert.Equal(t, []string{"xhci_pci", "ahci", "nvme", "sd_mod"}, profile.InitrdAvailableKernelModules)
	assert.Empty(t, profile.InitrdKernelModules)
	assert.Empty(t, profile.KernelModules)
	assert.Empty(t, profile.HostPlatform)
}

func TestParseGeneratedHardwareConfig_NonIntelKeepsModulesAndPlatform(t *testing.T) {
	profile := ParseGeneratedHardwareConfig(generatedAmdConfig)

	assert.Empty(t, profile.Commons)
	assert.Equal(t, []string{"nvme", "usbhid"}, profile.InitrdAvailableKernelModules)
	assert.Equal(t, []string{"r8169"}, profile.InitrdKernelModules)
	assert.Equal(t, []string{"kvm-amd"}, profile.KernelModules)
	assert.Equal(t, "x86_64-linux", profile.HostPlatform)
}

func TestAddHardware_WritesModule(t *testing.T) {
	infraDirectory := t.TempDir()

	hardwareFile, err := AddHardware(AddHardwareOptions{
		InfraDirectory: infraDirectory,
		Name:           "nuc-11",
		Profile:        ParseGeneratedHardwareConfig(generatedIntelConfig),
	})

	assert.NoError(t, err)
	assert.Equal(t, filepath.Join(infraDirectory, "nixos", "modules", "nixos", "hardware", "nuc-11", "default.nix"), hardwareFile)
	content, err := os.ReadFile(hardwareFile)
	assert.NoError(t, err)
	assert.Equal(t, `{ config, lib, ... }:

{
  config = lib.mkMerge [
    { bcl.hardware.knownDevices = [ "nuc-11" ]; }
    (lib.mkIf (config.bcl.hardware.device == "nuc-11") {
      bcl.hardware.commons = [ "intel" ];
      boot.initrd.availableKernelModules = [ "xhci_pci" "ahci" "nvme" "sd_mod" ];
    })
  ];
}
`, string(content))
}

func TestAddHardware_EmptyProfileWritesSkeleton(t *testing.T) {
	hardwareFile, err := AddHardware(AddHardwareOptions{InfraDirectory: t.TempDir(), Name: "custom"})

	assert.NoError(t, err)
	content, err := os.ReadFile(hardwareFile)
	assert.NoError(t, err)
	assert.Contains(t, string(content), `(lib.mkIf (config.bcl.hardware.device == "custom") {`+"\n    })")
}

func TestAddHardware_RefusesExistingHardware(t *testing.T) {
	infraDirectory := t.TempDir()
	_, err := AddHardware(AddHardwareOptions{InfraDirectory: infraDirectory, Name: "nuc"})
	assert.NoError(t, err)

	_, err = AddHardware(AddHardwareOptions{InfraDirectory: infraDirectory, Name: "nuc"})
	assert.Error(t, err)
}

func TestAddHardware_RejectsInvalidName(t *testing.T) {
	_, err := AddHardware(AddHardwareOptions{InfraDirectory: t.TempDir(), Name: "Bad Name"})
	assert.Error(t, err)
}

type fakeRunner struct {
	runner.Runner
	outputs map[string]string
}

func (f fakeRunner) ExecCmdGetStdout(head string, args ...string) (string, error) {
	return f.outputs[head], nil
}

func TestDetectHardwareProfile_ParsesHostOutput(t *testing.T) {
	profile, err := DetectHardwareProfile(fakeRunner{outputs: map[string]string{"nixos-generate-config": generatedIntelConfig}})

	assert.NoError(t, err)
	assert.Equal(t, []string{"intel"}, profile.Commons)
}

func TestDetectHardwareName_SlugifiesProductName(t *testing.T) {
	name, err := DetectHardwareName(fakeRunner{outputs: map[string]string{"cat": "NUC11PAHi7 \n"}})
	assert.NoError(t, err)
	assert.Equal(t, "nuc11pahi7", name)

	name, err = DetectHardwareName(fakeRunner{outputs: map[string]string{"cat": "ThinkPad T14 Gen 2\n"}})
	assert.NoError(t, err)
	assert.Equal(t, "thinkpad-t14-gen-2", name)

	_, err = DetectHardwareName(fakeRunner{outputs: map[string]string{"cat": "\n"}})
	assert.Error(t, err)
}
