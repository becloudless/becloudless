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

// lsblkNode is a single row of the system-wide block device tree.
type lsblkNode struct {
	Name       string
	Type       string
	MountPoint string
	PKName     string
	Tran       string
}

// blockDeviceGraph indexes every block device on the system so that any
// disk, partition, mapper (LUKS) or raid device, or one of its by-id /
// by-uuid / by-path / /dev/mapper links, can be resolved to its ancestor
// physical disk(s) and/or a mounted descendant, regardless of whether the
// given device itself is currently mounted.
type blockDeviceGraph struct {
	byName   map[string]lsblkNode
	byCanon  map[string]lsblkNode
	children map[string][]string
}

// loadBlockDeviceGraph lists every block device on the system (lsblk with no
// device argument walks the whole tree).
func loadBlockDeviceGraph(run runner.Runner) (*blockDeviceGraph, error) {
	out, err := run.ExecCmdGetStdout("lsblk", "-rnpo", "NAME,TYPE,MOUNTPOINT,PKNAME,TRAN")
	if err != nil {
		return nil, errs.WithE(err, "Failed to list system block devices")
	}

	g := &blockDeviceGraph{
		byName:   map[string]lsblkNode{},
		byCanon:  map[string]lsblkNode{},
		children: map[string][]string{},
	}
	for _, line := range strings.Split(strings.TrimRight(out, "\n"), "\n") {
		if line == "" {
			continue
		}
		fields := strings.SplitN(line, " ", 5)
		for len(fields) < 5 {
			fields = append(fields, "")
		}
		node := lsblkNode{Name: fields[0], Type: fields[1], MountPoint: fields[2], PKName: fields[3], Tran: fields[4]}
		g.byName[node.Name] = node
		g.byCanon[canonicalDevice(run, node.Name)] = node
		if node.PKName != "" {
			g.children[node.PKName] = append(g.children[node.PKName], node.Name)
		}
	}
	return g, nil
}

// find resolves arg (an lsblk NAME such as /dev/mapper/nix or /dev/nvme0n1,
// or a symlink to one such as a /dev/disk/by-id/... path) to its node.
func (g *blockDeviceGraph) find(run runner.Runner, arg string) (lsblkNode, bool) {
	if node, ok := g.byName[arg]; ok {
		return node, true
	}
	if node, ok := g.byCanon[canonicalDevice(run, arg)]; ok {
		return node, true
	}
	return lsblkNode{}, false
}

// descendMountPoint searches name and its descendants (in tree order) for
// the first mounted device, e.g. resolving a raw disk down through a LUKS
// mapper device to find where the mapped volume is mounted.
func (g *blockDeviceGraph) descendMountPoint(name string) (string, bool) {
	queue := []string{name}
	seen := map[string]bool{}
	for len(queue) > 0 {
		cur := queue[0]
		queue = queue[1:]
		if seen[cur] {
			continue
		}
		seen[cur] = true
		if node, ok := g.byName[cur]; ok && node.MountPoint != "" {
			return node.MountPoint, true
		}
		queue = append(queue, g.children[cur]...)
	}
	return "", false
}

// relatedChain returns name plus all of its ancestors (walking up PKName,
// e.g. partition -> disk) and descendants (e.g. partition -> LUKS mapper),
// as a []blockDevice suitable for findDiskByChain / physicalDeviceNames.
func (g *blockDeviceGraph) relatedChain(name string) []blockDevice {
	seen := map[string]bool{}
	var chain []blockDevice
	add := func(n string) {
		if seen[n] {
			return
		}
		seen[n] = true
		if node, ok := g.byName[n]; ok {
			chain = append(chain, blockDevice{Name: node.Name, Type: node.Type})
		}
	}

	for cur := name; cur != ""; {
		add(cur)
		node, ok := g.byName[cur]
		if !ok {
			break
		}
		cur = node.PKName
	}

	queue := append([]string{}, g.children[name]...)
	for len(queue) > 0 {
		cur := queue[0]
		queue = queue[1:]
		add(cur)
		queue = append(queue, g.children[cur]...)
	}

	return chain
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

// byIDPathPreferredPrefixes orders /dev/disk/by-id link name prefixes by
// preference: vendor/serial-based links (ata-, nvme-, scsi-) are more
// descriptive and are preferred over generic links (e.g. wwn-) when a
// device has more than one by-id link.
var byIDPathPreferredPrefixes = []string{"ata-", "nvme-", "scsi-"}

// byIDPath resolves a physical device name (e.g. "/dev/sdi") to a
// /dev/disk/by-id/... link. lsblk's ID-LINK column only ever returns a
// single (somewhat arbitrarily chosen) link per device, which for some
// disks is a generic wwn- link even though a more descriptive ata- link
// also exists; to get consistent, descriptive output this instead scans
// every /dev/disk/by-id/ entry pointing at the device and prefers a
// vendor/serial-based link. Falls back to the original device name if no
// by-id link can be found.
func byIDPath(run runner.Runner, deviceName string) string {
	out, err := run.ExecCmdGetStdout("ls", "-1", "/dev/disk/by-id")
	if err != nil {
		return deviceName
	}

	target := canonicalDevice(run, deviceName)

	var links []string
	for _, name := range strings.Split(strings.TrimSpace(out), "\n") {
		if name == "" {
			continue
		}
		if canonicalDevice(run, "/dev/disk/by-id/"+name) == target {
			links = append(links, name)
		}
	}

	for _, prefix := range byIDPathPreferredPrefixes {
		for _, link := range links {
			if strings.HasPrefix(link, prefix) {
				return "/dev/disk/by-id/" + link
			}
		}
	}
	if len(links) > 0 {
		return "/dev/disk/by-id/" + links[0]
	}
	return deviceName
}

// deviceInfoForPhysicalName builds the deviceInfo for a resolved physical
// device name (e.g. "/dev/nvme0n1"): if it matches one of the disk's
// configured devices, the configured by-id path and location are reused;
// otherwise the by-id link is resolved directly from the physical device.
func deviceInfoForPhysicalName(devices []bcl.DeviceConfig, run runner.Runner, deviceName string) deviceInfo {
	for _, device := range devices {
		if canonicalDevice(run, device.Path) == deviceName {
			return deviceInfo{Path: device.Path, Location: device.Location}
		}
	}
	return deviceInfo{Path: byIDPath(run, deviceName)}
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
			"The argument can be the disk name, a mount point, a path within a mount point, or a block\n" +
			"device (a raw disk, partition, LUKS mapper, raid device, or a /dev/disk/by-id|by-uuid|by-path link).\n" +
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
			var chain []blockDevice

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
							Path:     device.Path,
							Location: device.Location,
						})
					}
				}
			} else {
				graph, err := loadBlockDeviceGraph(run)
				if err != nil {
					return errs.WithEF(err, data.WithField("arg", arg), "Failed to resolve disk from argument")
				}

				if node, found := graph.find(run, arg); found {
					// arg is a block device (raw disk, partition, mapper,
					// raid device, or a link to one): find its physical
					// disk(s) and any mounted descendant directly from the
					// system's block device tree.
					chain = graph.relatedChain(node.Name)
					if mp, ok := graph.descendMountPoint(node.Name); ok {
						mountPoint = mp
					}
				} else {
					// Not a recognized block device: treat arg as a mount
					// point, or an arbitrary path within one.
					out, err := run.ExecCmdGetStdout("findmnt", "-n", "-o", "TARGET", "--target", arg)
					if err != nil {
						return errs.WithEF(err, data.WithField("arg", arg), "Failed to resolve mount point")
					}
					mountPoint = strings.TrimSpace(out)

					sourceOut, err := run.ExecCmdGetStdout("findmnt", "-n", "-o", "SOURCE", "--target", mountPoint)
					if err != nil {
						return errs.WithEF(err, data.WithField("mountPoint", mountPoint), "Failed to resolve mount source")
					}
					source := strings.TrimSpace(sourceOut)
					// findmnt appends a "[subvol-path]" suffix to SOURCE for
					// bind mounts / btrfs subvolumes (e.g.
					// "/dev/mapper/nix[/home/user]"); strip it.
					if idx := strings.IndexByte(source, '['); idx != -1 {
						source = source[:idx]
					}
					if node, found := graph.find(run, source); found {
						chain = graph.relatedChain(node.Name)
					}
				}
			}

			if mountPoint != "" {
				info.Path = mountPoint
			}

			if info.Name == "" && chain != nil {
				if name, found := findDiskByChain(disks, run, chain); found {
					info.Name = name
					matchedDevices = disks[name]
				}
			}

			if chain != nil {
				info.Devices = nil
				for _, deviceName := range physicalDeviceNames(chain) {
					info.Devices = append(info.Devices, deviceInfoForPhysicalName(matchedDevices, run, deviceName))
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
