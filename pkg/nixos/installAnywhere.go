package nixos

import (
	"encoding/json"
	"github.com/becloudless/becloudless/pkg/bcl"
	"github.com/becloudless/becloudless/pkg/system"
	"github.com/becloudless/becloudless/pkg/system/runner"
	"github.com/becloudless/becloudless/pkg/utils"
	"github.com/n0rad/go-erlog/data"
	"github.com/n0rad/go-erlog/errs"
	"github.com/n0rad/go-erlog/logs"
	"gopkg.in/yaml.v3"
	"os"
	"path"
	"strconv"
	"strings"
)

func InstallAnywhere(host string, user string, password []byte) error {
	run, err := runner.NewSshRunner(host, user, password)
	if err != nil {
		return errs.WithE(err, "Failed to connect to host to install")
	}

	//sudoRunner, err := runner.NewSudoRunner(run, password)
	sudoRunner, err := runner.NewInlineSudoRunner(run, password)
	if err != nil {
		return errs.WithE(err, "Sudo cannot be run successfully on host to install")
	}

	sys := system.System{
		SudoRunner: sudoRunner,
	}

	logs.Info("Extract system information from host to install")
	info, err := ExtractSystemInfo(sys)
	if err != nil {
		return errs.WithE(err, "Failed to extract system information from host to install")
	}

	logs.Info("Looking for matching system")
	localRunner := runner.NewLocalRunner()
	systemName, err := findSystem(localRunner, info)
	if err != nil {
		return errs.WithE(err, "Fail during process to find the system to install")
	}
	var systemConfig SystemConfig
	if systemName == "" {
		logs.Warn("Unkown system, creating")
		systemConfig, err = createSystemConfig(err, info)
		if err != nil {
			return errs.WithE(err, "System creation failed")
		}
	} else {
		logs.WithField("name", systemName).Info("System found")
		systemConfig = SystemConfig{Name: systemName}
		systemFolder := path.Join(bcl.BCL.Repository.Root, "nixos", "systems", "x86_64-linux", systemName)
		systemYamlFile := path.Join(systemFolder, "default.yaml")
		file, err := os.ReadFile(systemYamlFile)
		if err != nil {
			return errs.WithE(err, "Failed to read system yaml file")
		}
		if err := yaml.Unmarshal(file, systemConfig); err != nil {
			return errs.WithEF(err, data.WithField("file", systemYamlFile), "system yaml file looks broken")
		}
		//TODO use nix instead 	role=$(nix --extra-experimental-features "nix-command flakes" eval "$DIR/../nixos#nixosConfigurations.$hostname.config.system.nixos.tags" | sed 's/.*role-\([a-z0-9-]*\).*/\1/')
	}

	logs.WithField("system", systemName).Info("Starting installation")
	if _, err := localRunner.Exec(&[]string{"SSHPASS=" + string(password)}, nil, nil, nil,
		"nix-shell", "--extra-experimental-features", "nix-command flakes", "-p", "nixos-anywhere", "--run",
		"nixos-anywhere --env-password --flake "+path.Join(bcl.BCL.Repository.Root, "nixos")+"#"+systemName+" "+user+"@"+host); err != nil {
		return errs.WithE(err, "Installation failed")
	}

	//if err := localRunner.ExecCmd("nix-shell", "--extra-experimental-features", "nix-command flakes", "-p", "nixos-anywhere", "--run", "nixos-anywhere --flake "+path.Join(bcl.BCL.Repository.Root, "nixos")+"#"+systemName+" "+user+"@"+host); err != nil {
	//	return errs.WithE(err, "Installation failed")
	//}

	// ask cryptsetup passwprd
	// extract ssh host key for role to prepared folder
	// trigger nixos-anywhere

	return nil
}

func createSystemConfig(err error, info SystemInfo) (SystemConfig, error) {
	config, err := newSystemConfig(info)
	if err != nil {
		return config, errs.WithE(err, "Failed to create new host")
	}

	systemFolder := path.Join(bcl.BCL.Repository.Root, "nixos", "systems", "x86_64-linux", config.Name)
	if err := os.MkdirAll(systemFolder, 0755); err != nil {
		return config, errs.WithE(err, "Failed to create git system folder")
	}

	if err := utils.CopyFile(path.Join(bcl.BCL.AssetsPath, "repository", "nixos", "yamlSystem.nix"), path.Join(systemFolder, "default.nix")); err != nil {
		return config, errs.WithE(err, "Failed to copy system's default.nix")
	}

	systemYamlFile := path.Join(systemFolder, "default.yaml")
	file, err := os.OpenFile(systemYamlFile, os.O_RDWR|os.O_CREATE|os.O_TRUNC, 0644)
	if err != nil {
		return config, errs.WithE(err, "Failed to open nix system file")
	}
	defer file.Close()
	out, err := yaml.Marshal(config)
	if err != nil {
		return config, errs.WithE(err, "failed to marshal system configuration")
	}
	if _, err := file.Write(out); err != nil {
		return config, errs.WithE(err, "Failed to write system configuration to file")
	}

	if err := bcl.BCL.Repository.AddAll(); err != nil {
		return config, errs.WithE(err, "Failed to add new system to git repository")
	}
	return config, nil
}

func findSystem(localRunner *runner.LocalRunner, info SystemInfo) (string, error) {
	flakeShow, err := localRunner.ExecCmdGetStdout("nix", "--extra-experimental-features", "nix-command flakes",
		"flake", "show", path.Join(bcl.BCL.Repository.Root, "nixos"), "--json", "--all-systems")
	if err != nil {
		return "", errs.WithE(err, "Listing hosts declared in nix failed")
	}

	flake := struct {
		NixosConfigurations map[string]any `json:"nixosConfigurations"`
	}{}

	if err := json.Unmarshal([]byte(flakeShow), &flake); err != nil {
		return "", errs.WithE(err, "Failed to list nixos configurations")
	}

	for confName, _ := range flake.NixosConfigurations {
		ids, err := localRunner.ExecCmdGetStdout("nix", "--extra-experimental-features", "nix-command flakes", "eval", path.Join(bcl.BCL.Repository.Root, "nixos")+"#nixosConfigurations."+confName+".config.environment.etc.\"ids.env\".text", "--raw")
		if err != nil {
			logs.WithField("system", confName).Warn("system config is probably broken")
		}
		if ids == "uuid="+info.MotherboardUuid {
			return confName, nil
		}
	}
	return "", nil
}

type SystemInfo struct {
	MotherboardUuid string
	CpuSerial       string
	NetworkMacs     []string
	NetworkIps      []string
	Disks           []string
	EFI             bool
	Memory          int
}

const motherboardUuid = "motherboardUuid"
const cpuSerial = "cpuSerial"
const netWorkMacs = "netWorkMacs"
const netWorkIps = "netWorkIps"
const disks = "disks"
const efi = "efi"
const memory = "memory"

func ExtractSystemInfo(sys system.System) (SystemInfo, error) {
	// TODO available memory
	// TODO UEFI support

	info := SystemInfo{}
	res, err := sys.SudoRunner.ExecCmdGetStdout(`\
		echo "` + motherboardUuid + `=$(sudo -S cat /sys/devices/virtual/dmi/id/product_uuid 2> /dev/null)" > /tmp/info
		echo "` + cpuSerial + `=$(grep "Serial" /proc/cpuinfo | cut -f2 -d: | sed -e 's/^[[:space:]]*//')" >> /tmp/info
		echo "` + netWorkMacs + `=$(find /sys/class/net/*/ -maxdepth 1 -type l -name device -exec sh -c "grep -q up \$(dirname {})/operstate && cat \$(dirname {})/address | tr '\n' ','" \;)" >> /tmp/info
		echo "` + netWorkIps + `=$(ip -o addr show scope global | grep -E ": (wl|en|br)" | awk '{gsub(/\/.*/,"",$4); print $4}' | tr '\n' ',')" >> /tmp/info
		echo "` + disks + `=$(find /dev/disk/by-id/ -lname '*sd*' -o  -lname '*nvme*' -o -lname '*vd*' -o -lname '*scsi*' | grep -E -v -- "-part?" | grep '/ata\|/nvme\|usb\|/scsi'| tr '\n' ',')" >> /tmp/info
		echo "[ -d /sys/firmware/efi ] && ` + efi + `=true || ` + efi + `=false" >> /tmp/info
		echo "` + memory + `=$( cat /proc/meminfo | grep MemTotal: | awk '{ print $2; }')" >> /tmp/info
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
		case efi:
			if keyValue[1] == "true" {
				info.EFI = true
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
