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

type diskInfo struct {
	Name     string   `json:"name,omitempty" yaml:"name,omitempty"`
	Path     string   `json:"path,omitempty" yaml:"path,omitempty"`
	Location string   `json:"location,omitempty" yaml:"location,omitempty"`
	Devices  []string `json:"devices,omitempty" yaml:"devices,omitempty"`
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

// resolvePhysicalDevices resolves the underlying physical block device(s) backing
// a mount point, walking down through any device-mapper / LVM / mdraid layers
// (e.g. a LUKS mapper device) to the real disk(s) (e.g. /dev/nvme0n1).
func resolvePhysicalDevices(run runner.Runner, mountPoint string) ([]string, error) {
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
		return nil, errs.WithEF(err, data.WithField("source", source), "Failed to resolve physical device")
	}

	var devices []string
	for _, line := range strings.Split(strings.TrimSpace(lsblkOut), "\n") {
		fields := strings.Fields(line)
		if len(fields) == 2 && fields[1] == "disk" {
			devices = append(devices, fields[0])
		}
	}
	return devices, nil
}

func findDiskByMountPoint(disks map[string]bcl.DiskConfig, mountPoint string) (string, bool) {
	for name, disk := range disks {
		if disk.Path == mountPoint {
			return name, true
		}
	}
	return "", false
}

func nixosHardwareDisksInfoCmd() *cobra.Command {
	var outputFormat string

	cmd := &cobra.Command{
		Use:   "info <disk>",
		Short: "get info of a disk",
		Long: "Print info (path, location, physical devices) of a bcl.disks entry, as configured in /etc/bcl/config.yaml.\n" +
			"The argument can be the disk name, a mount point, a path within a mount point, or a block device.\n" +
			"Physical devices are resolved by walking down through any LUKS/LVM/mdraid layers to the real disk(s) (e.g. /dev/nvme0n1).\n" +
			"If the disk is not declared in the config, its resolved mount point is still printed, with an empty location.",
		Args: cobra.ExactArgs(1),
		RunE: func(cmd *cobra.Command, args []string) error {
			arg := args[0]
			disks := bcl.BCL.System.Disks
			run := runner.NewLocalRunner()

			var info diskInfo
			var mountPoint string

			if disk, ok := disks[arg]; ok {
				resolvedMountPoint, err := resolveDiskMountPoint(run, disk.Path)
				if err != nil {
					return errs.WithEF(err, data.WithField("arg", arg).WithField("path", disk.Path), "Failed to resolve mount point for disk")
				}
				mountPoint = resolvedMountPoint
				info = diskInfo{Name: arg, Path: mountPoint, Location: disk.Location}
			} else {
				resolvedMountPoint, err := resolveDiskMountPoint(run, arg)
				if err != nil {
					return errs.WithEF(err, data.WithField("arg", arg), "Failed to resolve disk from argument")
				}
				mountPoint = resolvedMountPoint

				if name, found := findDiskByMountPoint(disks, mountPoint); found {
					disk := disks[name]
					info = diskInfo{Name: name, Path: mountPoint, Location: disk.Location}
				} else {
					// Not declared in bcl.disks: still report what we resolved from the system.
					info = diskInfo{Path: mountPoint}
				}
			}

			devices, err := resolvePhysicalDevices(run, mountPoint)
			if err != nil {
				return errs.WithEF(err, data.WithField("mountPoint", mountPoint), "Failed to resolve physical device")
			}
			info.Devices = devices

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
