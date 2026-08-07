package disks

import (
	"encoding/json"
	"fmt"
	"slices"
	"sort"

	"github.com/becloudless/becloudless/pkg/bcl"
	"github.com/becloudless/becloudless/pkg/system/runner"
	"github.com/n0rad/go-erlog/data"
	"github.com/n0rad/go-erlog/errs"
	"github.com/spf13/cobra"
	"gopkg.in/yaml.v3"
)

const (
	diskStatusMounted    = "mounted"
	diskStatusNotMounted = "not-mounted"
	diskStatusMissing    = "missing"
)

var validDiskStatuses = []string{diskStatusMounted, diskStatusNotMounted, diskStatusMissing}

func nixosHardwareDisksListCmd() *cobra.Command {
	var outputFormat string
	var statusFilter []string

	cmd := &cobra.Command{
		Use:   "list",
		Short: "list disks on the system",
		Long: "List physical disks present on the system, enriched with the matching bcl.disks entry\n" +
			"(name, per-device location) from /etc/bcl/config.yaml, and its current mount point if mounted.\n" +
			"Disks configured in bcl.disks but not currently present on the system are also listed, with\n" +
			"status \"missing\". Use --status to only show disks in specific states.",
		Args: cobra.NoArgs,
		RunE: func(cmd *cobra.Command, args []string) error {
			for _, status := range statusFilter {
				if !slices.Contains(validDiskStatuses, status) {
					return errs.WithF(data.WithField("status", status), "Invalid status filter, must be one of: mounted, not-mounted, missing")
				}
			}

			disks := bcl.BCL.System.Disks
			run := runner.NewLocalRunner()

			graph, err := loadBlockDeviceGraph(run)
			if err != nil {
				return errs.WithE(err, "Failed to list system block devices")
			}

			var physicalDiskNames []string
			for name, node := range graph.byName {
				// Skip network-attached block devices (e.g. iSCSI-backed
				// Kubernetes CSI volumes), which report TYPE=disk but are
				// not physical disks of the machine.
				if node.Type == "disk" && node.Tran != "iscsi" {
					physicalDiskNames = append(physicalDiskNames, name)
				}
			}
			sort.Strings(physicalDiskNames)

			matchedNames := map[string]bool{}

			var infos []diskInfo
			for _, diskName := range physicalDiskNames {
				chain := graph.relatedChain(diskName)

				var info diskInfo
				var matchedDevices []bcl.DeviceConfig
				if name, found := findDiskByChain(disks, run, chain); found {
					info.Name = name
					matchedDevices = disks[name]
					matchedNames[name] = true
				}
				if mountPoint, ok := graph.descendMountPoint(diskName); ok {
					info.Path = mountPoint
					info.Status = diskStatusMounted
				} else {
					info.Status = diskStatusNotMounted
				}
				info.Devices = []deviceInfo{deviceInfoForPhysicalName(matchedDevices, run, diskName)}

				infos = append(infos, info)
			}

			var missingNames []string
			for name := range disks {
				if !matchedNames[name] {
					missingNames = append(missingNames, name)
				}
			}
			sort.Strings(missingNames)
			for _, name := range missingNames {
				var devices []deviceInfo
				for _, device := range disks[name] {
					devices = append(devices, deviceInfoFromConfig(run, device))
				}
				infos = append(infos, diskInfo{Name: name, Status: diskStatusMissing, Devices: devices})
			}

			if len(statusFilter) > 0 {
				var filtered []diskInfo
				for _, info := range infos {
					if slices.Contains(statusFilter, info.Status) {
						filtered = append(filtered, info)
					}
				}
				infos = filtered
			}

			switch outputFormat {
			case "yaml":
				out, err := yaml.Marshal(infos)
				if err != nil {
					return errs.WithE(err, "Failed to marshal disk list")
				}
				fmt.Print(string(out))
			case "json":
				out, err := json.MarshalIndent(infos, "", "  ")
				if err != nil {
					return errs.WithE(err, "Failed to marshal disk list")
				}
				fmt.Println(string(out))
			default:
				return errs.WithF(data.WithField("output", outputFormat), "Invalid output format, must be 'json' or 'yaml'")
			}
			return nil
		},
	}

	cmd.Flags().StringVarP(&outputFormat, "output", "o", "yaml", "Output format: json or yaml")
	cmd.Flags().StringSliceVarP(&statusFilter, "status", "s", nil, "Filter by status: mounted, not-mounted, missing (default: all)")

	return cmd
}
