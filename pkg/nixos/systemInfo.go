package nixos

import (
	"slices"
	"strconv"
	"strings"

	"github.com/becloudless/becloudless/pkg/system"
	"github.com/n0rad/go-erlog/data"
	"github.com/n0rad/go-erlog/errs"
)

const motherboardUuid = "motherboardUuid"
const cpuSerial = "cpuSerial"
const networkMacs = "networkMacs"
const networkIps = "networkIps"
const disks = "disks"
const efi = "efi"
const memory = "memory"
const isInstaller = "isInstaller"

type SystemInfo struct {
	MotherboardUuid string
	CpuSerial       string
	NetworkMacs     []string
	NetworkIps      []string
	Disks           []string
	EFI             bool
	Memory          int
	IsInstaller     bool
}

func (s SystemInfo) Matches(other SystemInfo) bool {
	if s.MotherboardUuid != "" && s.MotherboardUuid == other.MotherboardUuid {
		return true
	}
	if s.CpuSerial != "" && s.CpuSerial == other.CpuSerial {
		return true
	}
	for _, mac := range s.NetworkMacs {
		if slices.Contains(other.NetworkMacs, mac) {
			return true
		}
	}
	for _, ip := range s.NetworkIps {
		if slices.Contains(other.NetworkIps, ip) {
			return true
		}
	}
	for _, disk := range s.Disks {
		if slices.Contains(other.Disks, disk) {
			return true
		}
	}
	return false
}

func SystemInfoFromEnvVars(envVars string) (SystemInfo, error) {
	info := SystemInfo{}

	keyValues := strings.Split(envVars, "\n")
	for _, keyValueString := range keyValues {
		if keyValueString == "" {
			continue
		}
		if !strings.Contains(keyValueString, "=") {
			return info, errs.WithF(data.WithField("content", keyValueString), "Received an envs without key=value")
		}

		keyValue := strings.SplitN(keyValueString, "=", 2)
		switch keyValue[0] {
		case motherboardUuid:
			info.MotherboardUuid = keyValue[1]
		case cpuSerial:
			info.CpuSerial = keyValue[1]
		case networkMacs:
			for _, s := range strings.Split(keyValue[1], ",") {
				if s != "" {
					info.NetworkMacs = append(info.NetworkMacs, s)
				}
			}
		case networkIps:
			for _, s := range strings.Split(keyValue[1], ",") {
				if s != "" {
					info.NetworkIps = append(info.NetworkIps, s)
				}
			}
		case disks:
			for _, s := range strings.Split(keyValue[1], ",") {
				if s != "" {
					info.Disks = append(info.Disks, s)
				}
			}
		case efi:
			if keyValue[1] == "true" {
				info.EFI = true
			}
		case isInstaller:
			if keyValue[1] == "true" {
				info.IsInstaller = true
			}
		case memory:
			mem, err := strconv.Atoi(keyValue[1])
			if err != nil {
				return info, errs.WithEF(err, data.WithField("content", keyValue[1]), "Failed to parse memory size")
			}
			info.Memory = mem
		}
	}
	return info, nil
}

func ExtractSystemInfo(sys system.System) (SystemInfo, error) {
	// TODO available memory
	// TODO UEFI support

	res, err := sys.SudoRunner.ExecCmdGetStdout(`\
		echo "` + motherboardUuid + `=$(command -v sudo > /dev/null && sudo cat /sys/devices/virtual/dmi/id/product_uuid 2> /dev/null || cat /sys/devices/virtual/dmi/id/product_uuid 2> /dev/null)" > /tmp/info
		echo "` + cpuSerial + `=$(grep "Serial" /proc/cpuinfo | cut -f2 -d: | sed -e 's/^[[:space:]]*//')" >> /tmp/info
		echo "` + networkMacs + `=$(find /sys/class/net/*/ -maxdepth 1 -type l -name device -exec sh -c "grep -q up \$(dirname {})/operstate && cat \$(dirname {})/address | tr '\n' ','" \;)" >> /tmp/info
		echo "` + networkIps + `=$(ip -o addr show scope global | grep -E ": (wl|en|br)" | awk '{gsub(/\/.*/,"",$4); print $4}' | tr '\n' ',')" >> /tmp/info
		echo "` + disks + `=$(find /dev/disk/by-id/ -lname '*sd*' -o  -lname '*nvme*' -o -lname '*vd*' -o -lname '*scsi*' | grep -E -v -- "-part?" | grep '/ata\|/nvme\|usb\|/scsi'| tr '\n' ',')" >> /tmp/info
		echo "[ -d /sys/firmware/efi ] && ` + efi + `=true || ` + efi + `=false" >> /tmp/info
		echo "` + memory + `=$(cat /proc/meminfo | grep MemTotal: | awk '{ print $2; }')" >> /tmp/info
		echo "` + isInstaller + `=$(if grep -Eq 'VARIANT_ID="?installer"?' /etc/os-release; then echo "true"; else echo "false"; fi)" >> /tmp/info
		cat /tmp/info
		rm /tmp/info
	`)
	if err != nil {
		return SystemInfo{}, errs.WithE(err, "Failed to extract system info")
	}

	return SystemInfoFromEnvVars(res)
}
