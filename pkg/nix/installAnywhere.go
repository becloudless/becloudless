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
	sys := system.System{
		Runner: run,
	}

	if err := sys.IsSudoWorking(sudoPassword); err != nil {
		return errs.WithE(err, "Sudo cannot be run successfully on host to install")
	}

	info, err := ExtractSystemInfo(sys)
	if err != nil {
		return errs.WithE(err, "Failed to extract system information from host to install")
	}

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
	res, err := sys.Runner.ExecCmdGetStdout(`
		echo "`+motherboardUuid+`=$(cat /sys/devices/virtual/dmi/id/product_uuid 2> /dev/null)" > /tmp/info
		echo "`+cpuSerial+`=$(grep "Serial" /proc/cpuinfo | cut -f2 -d: | sed -e 's/^[[:space:]]*//')" >> /tmp/info
		echo "`+netWorkMacs+`=$(find /sys/class/net/*/ -maxdepth 1 -type l -name device -exec sh -c "grep -q up \$(dirname {})/operstate && cat \$(dirname {})/address | tr '\n' ','" \;)" >> /tmp/info
		echo "`+netWorkIps+`=$(ip -o addr show scope global | grep -E ": (wl|en|br)" | awk '{gsub(/\/.*/," ",$4); print $4}' | tr '\n' ' ')" >> /tmp/info
		echo "`+disks+`=$(find /dev/disk/by-id/ -lname '*sd*' -o  -lname '*nvme*' -o -lname '*vd*' -o -lname '*scsi*' | grep -E -v -- "-part?" | grep '/ata\|/nvme\|usb\|/scsi'| tr '\n' ' ')" >> /tmp/info
		cat /tmp/info
		rm /tmp/info
	`, "")
	if err != nil {
		return info, errs.WithE(err, "Failed")
	}

	keyValues := strings.Split(res, "\r\n")
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

//func RunGetStdout(client *ssh.Client, cmd string) (string, error) {
//	session, err := client.NewSession()
//	var stdout bytes.Buffer
//	var stderr bytes.Buffer
//	session.Stdout = &stdout
//	session.Stderr = &stderr
//
//	if err != nil {
//		return "", errs.WithE(err, "Failed to open ssh session")
//	}
//	defer session.Close()
//
//	if err := session.Run(cmd); err != nil {
//		return "", errs.WithEF(err, data.WithField("stderr", stderr.String()), "Failed to info")
//	}
//	return stdout.String(), nil
//}
