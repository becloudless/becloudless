package nix

import (
	"fmt"
	"github.com/awnumar/memguard"
	"github.com/becloudless/becloudless/pkg/system"
	"github.com/becloudless/becloudless/pkg/system/runner"
	"github.com/n0rad/go-erlog/data"
	"github.com/n0rad/go-erlog/errs"
	"strings"
)

func InstallAnywhere(host string, user string, sudoPassword *memguard.LockedBuffer) error {
	run, err := runner.NewSshRunner(host, user)
	if err != nil {
		return err
	}

	//sudoRunner, err := runner.NewSudoRunner(run, sudoPassword)
	sudoRunner, err := runner.NewInlineSudoRunner(run, sudoPassword)
	if err != nil {
		return errs.WithE(err, "Sudo cannot be run successfully on host to install")
	}

	sys := system.System{
		SudoRunner: sudoRunner,
	}

	info, err := ExtractSystemInfo(sys)
	if err != nil {
		return errs.WithE(err, "Failed to extract system information from host to install")
	}

	// find host info in nixos config
	// find role associated to host
	// ask cryptsetup passwprd
	// extract ssh host key for role to prepared folder
	// trigger nixos-anywhere

	fmt.Println("Ready to install", info)

	return nil
}

type SystemInfo struct {
	MotherboardUuid string
	CpuSerial       string
	NetworkMacs     []string
	NetworkIps      []string
	Disks           []string
}

const motherboardUuid = "motherboardUuid"
const cpuSerial = "cpuSerial"
const netWorkMacs = "netWorkMacs"
const netWorkIps = "netWorkIps"
const disks = "disks"

func ExtractSystemInfo(sys system.System) (SystemInfo, error) {
	info := SystemInfo{}
	res, err := sys.SudoRunner.ExecCmdGetStdout(`\
		echo "` + motherboardUuid + `=$(sudo -S cat /sys/devices/virtual/dmi/id/product_uuid 2> /dev/null)" > /tmp/info
		echo "` + cpuSerial + `=$(grep "Serial" /proc/cpuinfo | cut -f2 -d: | sed -e 's/^[[:space:]]*//')" >> /tmp/info
		echo "` + netWorkMacs + `=$(find /sys/class/net/*/ -maxdepth 1 -type l -name device -exec sh -c "grep -q up \$(dirname {})/operstate && cat \$(dirname {})/address | tr '\n' ','" \;)" >> /tmp/info
		echo "` + netWorkIps + `=$(ip -o addr show scope global | grep -E ": (wl|en|br)" | awk '{gsub(/\/.*/," ",$4); print $4}' | tr '\n' ' ')" >> /tmp/info
		echo "` + disks + `=$(find /dev/disk/by-id/ -lname '*sd*' -o  -lname '*nvme*' -o -lname '*vd*' -o -lname '*scsi*' | grep -E -v -- "-part?" | grep '/ata\|/nvme\|usb\|/scsi'| tr '\n' ' ')" >> /tmp/info
		cat /tmp/info
		rm /tmp/info
	`)
	if err != nil {
		return info, errs.WithE(err, "Failed")
	}

	keyValues := strings.Split(res, "\n")
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
		case netWorkMacs:
			for _, s := range strings.Split(keyValue[1], ",") {
				if s != "" {
					info.NetworkMacs = append(info.NetworkMacs, s)
				}
			}
		case netWorkIps:
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
		}
	}
	return info, nil
}
