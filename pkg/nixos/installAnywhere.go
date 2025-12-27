package nixos

import (
	"bytes"
	"encoding/json"
	"os"
	"path"
	"strconv"
	"strings"

	"github.com/becloudless/becloudless/pkg/bcl"
	"github.com/becloudless/becloudless/pkg/security"
	"github.com/becloudless/becloudless/pkg/system"
	"github.com/becloudless/becloudless/pkg/system/runner"
	"github.com/becloudless/becloudless/pkg/utils"
	"github.com/n0rad/go-erlog/data"
	"github.com/n0rad/go-erlog/errs"
	"github.com/n0rad/go-erlog/logs"
	"gopkg.in/yaml.v3"
)

const fileFacter = "facter.json"

func InstallAnywhere(host string, port int, user string, password []byte, identifyFile string, diskPassword string) error {
	sshRunner, err := runner.NewSshRunner(host, port, user, password, identifyFile)
	if err != nil {
		return errs.WithE(err, "Failed to connect to host to install, is the user set? did it required a password?")
	}

	var finalRunner runner.Runner = sshRunner
	if user != "root" {
		//sshSudoRunner, err := runner.NewSudoRunner(sshRunner, password)
		sshSudoRunner, err := runner.NewInlineSudoRunner(sshRunner, password)
		if err != nil {
			return errs.WithE(err, "Sudo cannot be run successfully on host to install")
		}
		finalRunner = sshSudoRunner
	}

	sys := system.System{
		SudoRunner: finalRunner,
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
	systemParentFolder := path.Join(bcl.BCL.GetNixosDir(), "systems", "x86_64-linux")
	if systemName == "" {
		logs.Warn("Unkown system, creating")
		systemConfig, err = createSystemConfig(err, info)
		if err != nil {
			return errs.WithE(err, "System creation failed")
		}
		systemName = systemConfig.Name
	} else {
		logs.WithField("name", systemName).Info("System found")
		systemConfig = SystemConfig{Name: systemName}
		systemYamlFile := path.Join(systemParentFolder, systemName, "default.yaml")
		file, err := os.ReadFile(systemYamlFile)
		if err != nil {
			return errs.WithE(err, "Failed to read system yaml file")
		}
		if err := yaml.Unmarshal(file, &systemConfig); err != nil {
			return errs.WithEF(err, data.WithField("file", systemYamlFile), "system yaml file looks broken")
		}
		//TODO use nix instead 	role=$(nix --extra-experimental-features "nix-command flakes" eval "$DIR/../nixos#nixosConfigurations.$hostname.config.system.nixos.tags" | sed 's/.*role-\([a-z0-9-]*\).*/\1/')
	}

	anywhereRunner := runner.NewNixShellRunner(localRunner, "nixos-anywhere")
	logs.WithField("system", systemName).Info("Run kexec phase")

	argId := ""
	if identifyFile != "" {
		argId = " -i " + identifyFile + " "
	}
	argEnvPass := ""
	if len(password) > 0 {
		argEnvPass = " --env-password "
	}

	if _, err := anywhereRunner.Exec(&[]string{"SSHPASS=" + string(password)}, nil, nil, nil,
		"bash -x nixos-anywhere --debug -p "+strconv.Itoa(port)+argId+argEnvPass+" --generate-hardware-config nixos-facter "+path.Join(systemParentFolder, systemName, fileFacter)+" --phases kexec --flake "+bcl.BCL.GetNixosDir()+"#"+systemName+" "+user+"@"+host); err != nil {
		return errs.WithE(err, "kexec phase failed")
	}

	temp, err := os.MkdirTemp(os.TempDir(), "bcl-install")
	if err != nil {
		return errs.WithE(err, "Failed to create temp directory")
	}
	defer os.RemoveAll(temp)

	if err := prepareDiskPassword(temp, systemName, diskPassword); err != nil {
		return errs.WithE(err, "Failed to prepare disk password")
	}
	if err := prepareHostSshKeys(temp, systemName); err != nil {
		return errs.WithE(err, "Failed to prepare disk password")
	}

	logs.WithField("system", systemName).Info("Run disko,install,reboot phases")
	if _, err := anywhereRunner.Exec(&[]string{"SSHPASS=" + string(password)}, nil, nil, nil,

		// TODO ssh as root when kexec was neeeded
		"bash -x nixos-anywhere --debug --phases disko,install,reboot -p "+strconv.Itoa(port)+argId+argEnvPass+" --extra-files "+path.Join(temp, "fs")+" --disk-encryption-keys /root/secret.key "+path.Join(temp, "install", "secret.key")+" --flake "+bcl.BCL.GetNixosDir()+"#"+systemName+" "+user+"@"+host); err != nil {
		return errs.WithE(err, "disco,install,reboot phase failed")
	}
	return nil
}

func prepareHostSshKeys(temp string, systemName string) error {
	localRunner := runner.NewLocalRunner()
	groupName, err := localRunner.ExecCmdGetStdout("nix", "--extra-experimental-features", "nix-command flakes", "eval", bcl.BCL.GetNixosDir()+"#nixosConfigurations."+systemName+".config.bcl.group.name")
	if err != nil {
		return errs.WithE(err, "Failed to find group name of system")
	}

	sopsRunner := runner.NewNixShellRunner(localRunner, "sops")

	_, privAgeKey, err := security.Ed25519PrivateKeyFileToPublicAndPrivateAgeKeys(path.Join(bcl.BCL.Home, "secrets", bcl.PathEd25519KeyFile))
	if err != nil {
		return errs.WithE(err, "Failed to load age key from ed25519 private key")
	}

	envs := []string{"SOPS_AGE_KEY=" + privAgeKey}
	var stdout bytes.Buffer
	if _, err := sopsRunner.Exec(&envs, os.Stdin, &stdout, os.Stderr, "sops", "-d", path.Join(bcl.BCL.GetNixosDir(), "modules", "nixos", "groups", groupName, "default.secrets.yaml")); err != nil {
		return errs.WithE(err, "Failed to extract group secrets")
	}

	secretFile := GroupSecretFile{}
	if err := yaml.Unmarshal(stdout.Bytes(), &secretFile); err != nil {
		return errs.WithE(err, "Failed to unmarshal group secret file")
	}

	sshHostFolder := path.Join(temp, "fs", "nix", "etc", "ssh")
	if err := os.MkdirAll(sshHostFolder, 0755); err != nil {
		return errs.WithE(err, "Failed to create ssh host folder")
	}

	sshHostKeyFile := path.Join(sshHostFolder, "ssh_host_ed25519_key")
	if err := os.WriteFile(sshHostKeyFile, []byte(secretFile.SshHostEd25519Key), 0600); err != nil {
		return errs.WithE(err, "Failed to write temporary ssh host key file")
	}

	initrdSshHostKeyFile := path.Join(sshHostFolder, "initrd_ssh_host_ed25519_key")
	if err := os.WriteFile(initrdSshHostKeyFile, []byte(secretFile.InitrdSshHostEd25519Key), 0600); err != nil {
		return errs.WithE(err, "Failed to write temporary initrd ssh host key file")
	}

	return nil
}

func prepareDiskPassword(temp string, systemName string, diskPassword string) error {
	localRunner := runner.NewLocalRunner()
	logs.WithField("system", systemName).Info("Check if disk password is required")
	device, err := localRunner.ExecCmdGetStdout("nix", "--extra-experimental-features", "nix-command flakes", "eval", bcl.BCL.GetNixosDir()+"#nixosConfigurations."+systemName+".config.fileSystems.\"/nix\".device")
	if err != nil {
		return errs.WithE(err, "Failed to check if a password is required for the disk")
	}
	if strings.Contains(device, "/dev/mapper") {
		if diskPassword == "" {
			pass, err := utils.AskPassword("Disk encryption password?", "Password do not match")
			if err != nil {
				return errs.WithE(err, "asking disk password failed")
			}
			diskPassword = string(pass)
		}
	}

	installDir := path.Join(temp, "install")
	if err := os.MkdirAll(installDir, 0700); err != nil {
		return errs.WithE(err, "Failed to create install temp directory")
	}
	diskPasswordFile := path.Join(installDir, "secret.key")
	if err := os.WriteFile(diskPasswordFile, []byte(diskPassword), 0600); err != nil {
		return errs.WithE(err, "Failed to write disk secret file")
	}
	return nil
}

func createSystemConfig(err error, info SystemInfo) (SystemConfig, error) {
	config, err := newSystemConfig(info)
	if err != nil {
		return config, errs.WithE(err, "Failed to create new host")
	}

	systemFolder := path.Join(bcl.BCL.GetNixosDir(), "systems", "x86_64-linux", config.Name)
	if err := os.MkdirAll(systemFolder, 0755); err != nil {
		return config, errs.WithE(err, "Failed to create git system folder")
	}

	if err := utils.CopyFile(path.Join(bcl.BCL.EmbeddedPath, "assets", "repository", "nixos", "yamlSystem.nix"), path.Join(systemFolder, "default.nix")); err != nil {
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

	if err := bcl.BCL.Repo.AddAll(); err != nil {
		return config, errs.WithE(err, "Failed to add new system to git repository")
	}
	return config, nil
}

func findSystem(localRunner *runner.LocalRunner, info SystemInfo) (string, error) {
	flakeShow, err := localRunner.ExecCmdGetStdout("nix", "--extra-experimental-features", "nix-command flakes",
		"flake", "show", bcl.BCL.GetNixosDir(), "--json", "--all-systems")
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
		ids, err := localRunner.ExecCmdGetStdout("nix", "--extra-experimental-features", "nix-command flakes", "eval", bcl.BCL.GetNixosDir()+"#nixosConfigurations."+confName+".config.environment.etc.\"ids.env\".text", "--raw")
		if err != nil {
			logs.WithField("system", confName).Warn("system config is probably broken")
			continue
		}
		if ids == "uuid="+info.MotherboardUuid { // TODO this is definitly wrong
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
		echo "` + motherboardUuid + `=$(command -v sudo > /dev/null && sudo cat /sys/devices/virtual/dmi/id/product_uuid 2> /dev/null || cat /sys/devices/virtual/dmi/id/product_uuid 2> /dev/null)" > /tmp/info
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
