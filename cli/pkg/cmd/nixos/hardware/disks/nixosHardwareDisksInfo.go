package disks

import (
	"encoding/json"
	"fmt"
	"strings"

	"github.com/becloudless/becloudless/pkg/bcl"
	"github.com/becloudless/becloudless/pkg/system/runner"
	"github.com/n0rad/go-erlog/data"
	"github.com/n0rad/go-erlog/errs"
	"github.com/spf13/cobra"
	"gopkg.in/yaml.v3"
)

type deviceInfo struct {
	Path     string `json:"path,omitempty" yaml:"path,omitempty"`
	Location string `json:"location,omitempty" yaml:"location,omitempty"`
}

type diskInfo struct {
	Name    string       `json:"name,omitempty" yaml:"name,omitempty"`
	Path    string       `json:"path,omitempty" yaml:"path,omitempty"`
	Devices []deviceInfo `json:"devices,omitempty" yaml:"devices,omitempty"`
}

type blockDevice struct {
	Name string
	Type string
}

// resolveDiskMountPoint turns a block device, by-id path, mount point or
// arbitrary path inside a mount point into the mount point (TARGET) that
// covers it, using findmnt.
func resolveDiskMountPoint(run runner.Runner, arg string) (string, error) {
	// Try resolving as a block device / source first (e.g. /dev/sda1, /dev/disk/by-id/xxx).
	if out, err := run.ExecCmdGetStdout("findmnt", "-n", "-o", "TARGET", "--source", arg); err == nil {
		if target := strings.TrimSpace(out); target != "" {
			return target, nil
		}
	}

	// Fall back to treating arg as a path: findmnt --target resolves the
	// closest mount point above any given file or directory.
	out, err := run.ExecCmdGetStdout("findmnt", "-n", "-o", "TARGET", "--target", arg)
	if err != nil {
		return "", errs.WithEF(err, data.WithField("arg", arg), "Failed to resolve mount point")
	}
	return strings.TrimSpace(out), nil
}

// resolveBlockChain resolves the full chain of block devices (from the
// mounted source down to the underlying physical disk(s)), walking through
// any device-mapper / LVM / mdraid layers (e.g. a LUKS mapper device).
func resolveBlockChain(run runner.Runner, mountPoint string) ([]blockDevice, error) {
	out, err := run.ExecCmdGetStdout("findmnt", "-n", "-o", "SOURCE", "--target", mountPoint)
	if err != nil {
		return nil, errs.WithEF(err, data.WithField("mountPoint", mountPoint), "Failed to resolve mount source")
	}
	source := strings.TrimSpace(out)
	// findmnt appends a "[subvol-path]" suffix to SOURCE for bind mounts /
	// btrfs subvolumes (e.g. "/dev/mapper/nix[/home/user]"); strip it since
	// lsblk expects a plain device path.
	if idx := strings.IndexByte(source, '['); idx != -1 {
		source = source[:idx]
	}

	lsblkOut, err := run.ExecCmdGetStdout("lsblk", "-rsp", "-no", "NAME,TYPE", source)
	if err != nil {
		return nil, errs.WithEF(err, data.WithField("source", source), "Failed to resolve block device chain")
	}

	var chain []blockDevice
	for _, line := range strings.Split(strings.TrimSpace(lsblkOut), "\n") {
		fields := strings.Fields(line)
		if len(fields) == 2 {
			chain = append(chain, blockDevice{Name: fields[0], Type: fields[1]})
		}
	}
	return chain, nil
}

// physicalDeviceNames filters a block chain down to the underlying physical
// disk(s) (e.g. /dev/nvme0n1).
func physicalDeviceNames(chain []blockDevice) []string {
	var names []string
	for _, d := range chain {
		if d.Type == "disk" {
			names = append(names, d.Name)
		}
	}
	return names
}

// canonicalDevice resolves symlinks (e.g. /dev/disk/by-id/xxx) to their
// canonical device path (e.g. /dev/sda1). Falls back to the original value
// if it cannot be resolved (e.g. the device doesn't currently exist).
func canonicalDevice(run runner.Runner, device string) string {
	out, err := run.ExecCmdGetStdout("readlink", "-f", device)
	if err != nil {
		return device
	}
	if target := strings.TrimSpace(out); target != "" {
		return target
	}
	return device
}

// locationForDevice looks up the configured location for a resolved device
// name (e.g. "/dev/nvme0n1"), by canonicalizing each of the disk's
// configured device paths and comparing.
func locationForDevice(devices []bcl.DeviceConfig, run runner.Runner, deviceName string) string {
	for _, device := range devices {
		if canonicalDevice(run, device.Path) == deviceName {
			return device.Location
		}
	}
	return ""
}

// findDiskByChain finds a configured bcl.disks entry whose devices overlap
// with the given block device chain (which may include partitions, mdraid
// or LUKS mapper devices, and the underlying physical disk(s)).
func findDiskByChain(disks map[string][]bcl.DeviceConfig, run runner.Runner, chain []blockDevice) (string, bool) {
	chainNames := make(map[string]bool, len(chain))
	for _, d := range chain {
		chainNames[d.Name] = true
	}
	for name, devices := range disks {
		for _, device := range devices {
			if chainNames[canonicalDevice(run, device.Path)] {
				return name, true
			}
		}
	}
	return "", false
}

// mountPointCandidatesForDisk returns, in priority order, the possible
// top-level sources findmnt could report for a bcl.disks entry: the LUKS
// mapper device, the mdraid device, then each raw device.
func mountPointCandidatesForDisk(name string, devices []bcl.DeviceConfig) []string {
	candidates := []string{"/dev/mapper/" + name, "/dev/md/" + name}
	for _, device := range devices {
		candidates = append(candidates, device.Path)
	}
	return candidates
}

func nixosHardwareDisksInfoCmd() *cobra.Command {
	var outputFormat string

	cmd := &cobra.Command{
		Use:   "info <disk>",
		Short: "get info of a disk",
		Long: "Print info (path, devices, per-device location) of a bcl.disks entry, as configured in /etc/bcl/config.yaml.\n" +
			"The argument can be the disk name, a mount point, a path within a mount point, or a block device.\n" +
			"Physical devices are resolved by walking down through any LUKS/LVM/mdraid layers to the real disk(s) (e.g. /dev/nvme0n1).\n" +
			"If the disk is not declared in the config, its resolved mount point is still printed, with no location.",
		Args: cobra.ExactArgs(1),
		RunE: func(cmd *cobra.Command, args []string) error {
			arg := args[0]
			disks := bcl.BCL.System.Disks
			run := runner.NewLocalRunner()

			var info diskInfo
			var mountPoint string
			var matchedDevices []bcl.DeviceConfig

			if devices, ok := disks[arg]; ok {
				info.Name = arg
				matchedDevices = devices
				for _, candidate := range mountPointCandidatesForDisk(arg, devices) {
					if out, err := run.ExecCmdGetStdout("findmnt", "-n", "-o", "TARGET", "--source", candidate); err == nil {
						if target := strings.TrimSpace(out); target != "" {
							mountPoint = target
							break
						}
					}
				}
				if mountPoint == "" {
					// Disk not currently mounted: fall back to the devices declared in config.
					for _, device := range devices {
						info.Devices = append(info.Devices, deviceInfo{
							Path:     canonicalDevice(run, device.Path),
							Location: device.Location,
						})
					}
				}
			} else {
				resolvedMountPoint, err := resolveDiskMountPoint(run, arg)
				if err != nil {
					return errs.WithEF(err, data.WithField("arg", arg), "Failed to resolve disk from argument")
				}
				mountPoint = resolvedMountPoint
			}

			if mountPoint != "" {
				chain, err := resolveBlockChain(run, mountPoint)
				if err != nil {
					return errs.WithEF(err, data.WithField("mountPoint", mountPoint), "Failed to resolve physical device")
				}
				info.Path = mountPoint

				if matchedDevices == nil {
					if name, found := findDiskByChain(disks, run, chain); found {
						info.Name = name
						matchedDevices = disks[name]
					}
				}

				info.Devices = nil
				for _, deviceName := range physicalDeviceNames(chain) {
					location := locationForDevice(matchedDevices, run, deviceName)
					info.Devices = append(info.Devices, deviceInfo{Path: deviceName, Location: location})
				}
			}

			switch outputFormat {
			case "yaml":
				out, err := yaml.Marshal(info)
				if err != nil {
					return errs.WithE(err, "Failed to marshal disk info")
				}
				fmt.Print(string(out))
			case "json":
				out, err := json.MarshalIndent(info, "", "  ")
				if err != nil {
					return errs.WithE(err, "Failed to marshal disk info")
				}
				fmt.Println(string(out))
			default:
				return errs.WithF(data.WithField("output", outputFormat), "Invalid output format, must be 'json' or 'yaml'")
			}
			return nil
		},
	}

	cmd.Flags().StringVarP(&outputFormat, "output", "o", "yaml", "Output format: json or yaml")

	return cmd
}
