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
	"github.com/n0rad/go-erlog/errs"
	"github.com/n0rad/go-erlog/logs"
	"gopkg.in/yaml.v3"
)

const fileFacter = "facter.json"

func InstallAnywhere(sshConfig *runner.SshConnectionConfig, diskPassword string) error {
	infra, err := bcl.FindInfraFromPath(".")
	if err != nil {
		return errs.WithE(err, "Failed to open current infra repository")
	}

	sshRunner, err := runner.NewSshRunner(sshConfig)
	if err != nil {
		return errs.WithE(err, "Failed to connect to host to install, is the user set? did it required a password?")
	}

	var finalRunner runner.Runner = sshRunner
	if sshConfig.User != "root" {
		sshSudoRunner, err := runner.NewSudoRunner(sshRunner, sshConfig.Password)
		if err != nil {
			return errs.WithE(err, "Sudo cannot be run successfully on host to install")
		}
		finalRunner = sshSudoRunner.WithInline(true)
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
	systemName, err := findSystem(infra, localRunner, info)
	if err != nil {
		return errs.WithE(err, "Fail during process to find the system to install")
	}
	//var systemConfig SystemConfig
	//systemParentFolder := path.Join(infra.GetNixosDir(), "systems", "x86_64-linux")
	//if systemName == "" {
	//	logs.Warn("Unkown system, creating")
	//	systemConfig, err = createSystemConfig(infra, err, info)
	//	if err != nil {
	//		return errs.WithE(err, "System creation failed")
	//	}
	//	systemName = systemConfig.Name
	//} else {
	//	logs.WithField("name", systemName).Info("System found")
	//	systemConfig = SystemConfig{Name: systemName}
	//	systemYamlFile := path.Join(systemParentFolder, systemName, "default.yaml")
	//	file, err := os.ReadFile(systemYamlFile)
	//	if err != nil {
	//		return errs.WithE(err, "Failed to read system yaml file")
	//	}
	//	if err := yaml.Unmarshal(file, &systemConfig); err != nil {
	//		return errs.WithEF(err, data.WithField("file", systemYamlFile), "system yaml file looks broken")
	//	}
	//	//TODO use nix instead 	role=$(nix --extra-experimental-features "nix-command flakes" eval "$DIR/../nixos#nixosConfigurations.$hostname.config.system.nixos.tags" | sed 's/.*role-\([a-z0-9-]*\).*/\1/')
	//}

	anywhereRunner := runner.NewNixShellRunner(localRunner, "nixos-anywhere")
	logs.WithField("system", systemName).Info("Run kexec phase")

	nixosAnywhereArgs := []string{
		"--debug",
		"-p", strconv.Itoa(sshConfig.Port),
		"--flake", infra.GetNixosDir() + "#" + systemName,
	}

	if sshConfig.IdentifyFile != "" {
		nixosAnywhereArgs = append(nixosAnywhereArgs, "-i", sshConfig.IdentifyFile)
	}
	if sshConfig.Password.IsSet() {
		nixosAnywhereArgs = append(nixosAnywhereArgs, "--env-password")
	}

	sshPassword := ""
	if sshConfig.Password.IsSet() {
		openedPassword, err := sshConfig.Password.Get()
		if err != nil {
			return errs.WithE(err, "Failed to open ssh password enclave")
		}
		sshPassword = openedPassword.String()
	}

	// kexec
	if _, err := anywhereRunner.Exec(&[]string{"SSHPASS=" + sshPassword}, nil, nil, nil, "nixos-anywhere", append(nixosAnywhereArgs,
		"--phases", "kexec",
		sshConfig.User+"@"+sshConfig.Host,
	)...); err != nil {
		return errs.WithE(err, "kexec phase failed")
	}

	temp, err := os.MkdirTemp(os.TempDir(), "bcl-install")
	if err != nil {
		return errs.WithE(err, "Failed to create temp directory")
	}
	defer os.RemoveAll(temp)

	if err := prepareDiskPassword(infra, temp, systemName, diskPassword); err != nil {
		return errs.WithE(err, "Failed to prepare disk password")
	}
	if err := prepareHostSshKeys(infra, temp, systemName); err != nil {
		return errs.WithE(err, "Failed to prepare ssh host key")
	}

	installUser := "root"
	if info.IsInstaller {
		// was already running installer. No kexec was run
		installUser = sshConfig.User
	}

	logs.WithField("system", systemName).Info("Run disko,install,reboot phases")
	if _, err := anywhereRunner.Exec(&[]string{"SSHPASS=" + sshPassword}, nil, nil, nil, "nixos-anywhere", append(nixosAnywhereArgs,
		"--phases", "disko,install,reboot",
		"--extra-files", path.Join(temp, "fs"),
		"--disk-encryption-keys", "/root/secret.key", path.Join(temp, "install", "secret.key"),
		installUser+"@"+sshConfig.Host,
	)...); err != nil {
		return errs.WithE(err, "disco,install,reboot phase failed")
	}
	return nil
}

func prepareHostSshKeys(repo *bcl.Infra, temp string, systemName string) error {
	localRunner := runner.NewLocalRunner()

	groupName, err := localRunner.ExecCmdGetStdout(
		"nix",
		"--extra-experimental-features", "nix-command flakes",
		"eval", repo.GetNixosDir()+"#nixosConfigurations."+systemName+".config.bcl.group.name",
		"--raw")
	if err != nil {
		return errs.WithE(err, "Failed to find group name of system")
	}

	logs.WithField("system", systemName).WithField("group", groupName).Info("Extracting host ssh key for group")

	sopsRunner := runner.NewNixShellRunner(localRunner, "sops")

	_, privAgeKey, err := security.Ed25519PrivateKeyFileToPublicAndPrivateAgeKeys(path.Join(bcl.BCL.Home, "secrets", bcl.PathEd25519KeyFile))
	if err != nil {
		return errs.WithE(err, "Failed to load age key from ed25519 private key")
	}

	envs := []string{"SOPS_AGE_KEY=" + privAgeKey}
	var stdout bytes.Buffer
	if _, err := sopsRunner.Exec(&envs, os.Stdin, &stdout, os.Stderr, "sops", "-d", path.Join(repo.GetNixosDir(), "modules", "nixos", "groups", groupName, "default.secrets.yaml")); err != nil {
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

func prepareDiskPassword(repo *bcl.Infra, temp string, systemName string, diskPassword string) error {
	localRunner := runner.NewLocalRunner()
	logs.WithField("system", systemName).Info("Check if disk password is required")
	device, err := localRunner.ExecCmdGetStdout(
		"nix",
		"--extra-experimental-features", "nix-command flakes",
		"eval", repo.GetNixosDir()+"#nixosConfigurations."+systemName+".config.fileSystems.\"/nix\".device",
		"--raw")
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

func createSystemConfig(repo *bcl.Infra, err error, info SystemInfo) (SystemConfig, error) {
	config, err := newSystemConfig(info)
	if err != nil {
		return config, errs.WithE(err, "Failed to create new host")
	}

	systemFolder := path.Join(repo.GetNixosDir(), "systems", "x86_64-linux", config.Name)
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

	if err := repo.Git.AddAll(); err != nil {
		return config, errs.WithE(err, "Failed to add new system to git repository")
	}
	return config, nil
}

func findSystem(repo *bcl.Infra, localRunner *runner.LocalRunner, info SystemInfo) (string, error) {
	flakeShow, err := localRunner.ExecCmdGetStdout(
		"nix",
		"--extra-experimental-features", "nix-command flakes",
		"flake",
		"show",
		repo.GetNixosDir(),
		"--json",
		"--all-systems")
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
		ids, err := localRunner.ExecCmdGetStdout(
			"nix",
			"--extra-experimental-features", "nix-command flakes",
			"eval", repo.GetNixosDir()+"#nixosConfigurations."+confName+".config.environment.etc.\"ids.env\".text",
			"--raw")
		if err != nil {
			logs.WithField("system", confName).Warn("system config is probably broken")
			continue
		}

		current, err := SystemInfoFromEnvVars(ids)
		if err != nil {
			return "", errs.WithE(err, "Failed to parse ids from system config")
		}

		if current.Matches(info) {
			return confName, nil
		}
	}
	return "", nil
}
