package nixos

import (
	"bytes"
	"encoding/json"
	"fmt"
	"os"
	"path"
	"slices"
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

type InstallOptions struct {
	DiskPassword string
	BuildOn      string
	// System is the name of the system to install, when empty it is found with bcl.system.id or asked
	System    string
	AssumeYes bool
}

func InstallAnywhere(sshConfig *runner.SshConnectionConfig, options InstallOptions) error {
	diskPassword := options.DiskPassword
	buildOn := options.BuildOn
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
		sshSudoRunner, err := runner.NewSudoRunnerWithPassword(sshRunner, sshConfig.Password)
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

	logs.Info("Looking for the system to install")
	// nix flakes only see tracked files, so new systems must be added to git first
	if err := infra.Git.AddAll(); err != nil {
		return errs.WithE(err, "Failed to add new files to git repository")
	}
	localRunner := runner.NewLocalRunner()
	selection, err := selectSystem(infra, localRunner, info, options.System, options.AssumeYes)
	if err != nil {
		return errs.WithE(err, "Fail during process to find the system to install")
	}
	if err := confirmInstall(sshConfig.Host, selection, info, options.AssumeYes); err != nil {
		return err
	}
	systemName := selection.name
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
	if buildOn != "" {
		nixosAnywhereArgs = append(nixosAnywhereArgs, "--build-on", buildOn)
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

	sshHostFolder := path.Join(temp, "fs", "nix", "etc", "ssh")
	if err := os.MkdirAll(sshHostFolder, 0755); err != nil {
		return errs.WithE(err, "Failed to create ssh host folder")
	}

	secretFilePath, err := localRunner.ExecCmdGetStdout(
		"nix",
		"--extra-experimental-features", "nix-command flakes",
		"eval", repo.GetNixosDir()+"#nixosConfigurations."+systemName+".config.bcl.role.secretFile",
		"--raw")
	if err != nil {
		logs.WithField("system", systemName).Warn("System does not define bcl.role.secretFile, skipping ssh host key preparation")
		return nil
	}

	if secretFilePath == "" {
		logs.WithField("system", systemName).Warn("System has an empty bcl.role.secretFile, skipping ssh host key preparation")
		return nil
	}

	logs.WithField("system", systemName).WithField("secretFile", secretFilePath).Info("Extracting host ssh key from role secret file")

	sopsRunner := runner.NewNixShellRunner(localRunner, "sops")

	_, privAgeKey, err := security.Ed25519PrivateKeyFileToPublicAndPrivateAgeKeys(path.Join(bcl.BCL.ConfigFolder, "secrets", bcl.PathEd25519KeyFile))
	if err != nil {
		return errs.WithE(err, "Failed to load age key from ed25519 private key")
	}

	envs := []string{"SOPS_AGE_KEY=" + privAgeKey}
	var stdout bytes.Buffer
	if _, err := sopsRunner.Exec(&envs, os.Stdin, &stdout, os.Stderr, "sops", "-d", secretFilePath); err != nil {
		return errs.WithE(err, "Failed to extract group secrets")
	}

	secretFile := GroupSecretFile{}
	if err := yaml.Unmarshal(stdout.Bytes(), &secretFile); err != nil {
		return errs.WithE(err, "Failed to unmarshal group secret file")
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

type systemSelection struct {
	name string
	// matchedById is true when bcl.system.id of the system matched the target, so nothing was chosen by hand
	matchedById bool
	// idMismatch is true when the system declares a bcl.system.id that does not match the target
	idMismatch bool
}

func listSystems(repo *bcl.Infra, localRunner *runner.LocalRunner) ([]string, error) {
	flakeShow, err := localRunner.ExecCmdGetStdout(
		"nix",
		"--extra-experimental-features", "nix-command flakes",
		"flake",
		"show",
		repo.GetNixosDir(),
		"--json",
		"--all-systems")
	if err != nil {
		return nil, errs.WithE(err, "Listing hosts declared in nix failed")
	}

	flake := struct {
		NixosConfigurations map[string]any `json:"nixosConfigurations"`
	}{}

	if err := json.Unmarshal([]byte(flakeShow), &flake); err != nil {
		return nil, errs.WithE(err, "Failed to list nixos configurations")
	}

	names := make([]string, 0, len(flake.NixosConfigurations))
	for name := range flake.NixosConfigurations {
		names = append(names, name)
	}
	slices.Sort(names)
	return names, nil
}

func declaredSystemId(repo *bcl.Infra, localRunner *runner.LocalRunner, systemName string) (SystemInfo, error) {
	idJSON, err := localRunner.ExecCmdGetStdout(
		"nix",
		"--extra-experimental-features", "nix-command flakes",
		"eval", repo.GetNixosDir()+"#nixosConfigurations."+systemName+".config.bcl.system.id",
		"--json")
	if err != nil {
		return SystemInfo{}, errs.WithE(err, "Failed to evaluate bcl.system.id, system config is probably broken")
	}

	var declared SystemInfo
	if err := json.Unmarshal([]byte(idJSON), &declared); err != nil {
		return SystemInfo{}, errs.WithEF(err, data.WithField("id", idJSON), "Failed to parse bcl.system.id")
	}
	return declared, nil
}

// selectSystem uses the requested system, else the only system whose optional bcl.system.id matches the target, else asks
func selectSystem(repo *bcl.Infra, localRunner *runner.LocalRunner, info SystemInfo, requested string, assumeYes bool) (systemSelection, error) {
	names, err := listSystems(repo, localRunner)
	if err != nil {
		return systemSelection{}, err
	}

	if requested != "" {
		if !slices.Contains(names, requested) {
			return systemSelection{}, errs.WithF(data.WithField("system", requested).WithField("available", names), "System is not declared in the repository")
		}
		declared, err := declaredSystemId(repo, localRunner, requested)
		if err != nil {
			return systemSelection{}, errs.WithEF(err, data.WithField("system", requested), "Cannot read the system identity")
		}
		return systemSelection{name: requested, idMismatch: declared.HasIdentity() && !declared.Matches(info)}, nil
	}

	var matches []string
	for _, name := range names {
		declared, err := declaredSystemId(repo, localRunner, name)
		if err != nil {
			logs.WithEF(err, data.WithField("system", name)).Warn("Skipping system")
			continue
		}
		if declared.Matches(info) {
			matches = append(matches, name)
		}
	}

	switch len(matches) {
	case 1:
		return systemSelection{name: matches[0], matchedById: true}, nil
	case 0:
		if assumeYes {
			return systemSelection{}, errs.WithF(data.WithField("info", info), "No system matches the target, select one with --system")
		}
		chosen, err := utils.AskChoice("No system declares an id matching the target, which system to install?", names)
		if err != nil {
			return systemSelection{}, err
		}
		return systemSelection{name: chosen}, nil
	default:
		return systemSelection{}, errs.WithF(data.WithField("matches", matches), "Several systems match the target, select one with --system")
	}
}

// confirmInstall protects the target disks, nothing is asked when the system was found by its id
func confirmInstall(host string, selection systemSelection, info SystemInfo, assumeYes bool) error {
	if selection.idMismatch {
		logs.WithField("system", selection.name).Warn("The target does not match the bcl.system.id of the system")
		if assumeYes {
			return errs.WithF(data.WithField("system", selection.name), "The target does not match the bcl.system.id of the system, fix or remove the id")
		}
	}
	if selection.matchedById || assumeYes {
		return nil
	}

	fmt.Printf("Install system %q on %s, this erases its disks\n", selection.name, host)
	fmt.Printf("  disks:  %s\n", strings.Join(info.Disks, ", "))
	fmt.Printf("  macs:   %s\n", strings.Join(info.NetworkMacs, ", "))
	fmt.Printf("  memory: %d MiB\n", info.Memory/1024)
	confirmed, err := utils.AskConfirm("Install?")
	if err != nil {
		return err
	}
	if !confirmed {
		return errs.With("Install aborted")
	}
	return nil
}
