package nixos

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"

	"github.com/becloudless/becloudless/pkg/bcl"
	"github.com/becloudless/becloudless/pkg/cmd/flags"
	bclGit "github.com/becloudless/becloudless/pkg/git"
	"github.com/becloudless/becloudless/pkg/system/runner"
	"github.com/go-git/go-git/v6"
	"github.com/n0rad/go-erlog/data"
	"github.com/n0rad/go-erlog/errs"
	"github.com/n0rad/go-erlog/logs"
	"github.com/spf13/cobra"
)

func buildFlakeTarget(repository string, systemName string) string {
	base := repository
	fragment := ""

	if idx := strings.Index(base, "#"); idx >= 0 {
		fragment = base[idx+1:]
		base = base[:idx]
	}

	if !strings.Contains(base, "://") {
		if idx := strings.Index(base, ":"); idx >= 0 && !strings.HasPrefix(base, "/") {
			// scp-like syntax, e.g. git@gitea.lmr.fr:lmr/infra.git
			base = "git+ssh://" + base[:idx] + "/" + base[idx+1:]
		} else if !strings.HasPrefix(base, "/") {
			base = "git+ssh://" + base
		}
	}

	if strings.HasPrefix(base, "git+") && !strings.Contains(base, "dir=") {
		if strings.Contains(base, "?") {
			base += "&dir=nixos"
		} else {
			base += "?dir=nixos"
		}
	}

	if systemName != "" {
		return fmt.Sprintf("%s#%s", base, systemName)
	}

	if fragment != "" {
		return fmt.Sprintf("%s#%s", base, fragment)
	}

	return base
}

func nixosUpgradeCmd() *cobra.Command {
	var action string
	var sshConfig runner.SshConnectionConfig
	var systemName string
	var useLocalGitRepository bool
	var overrideInputs []string

	cmd := &cobra.Command{
		Use:     "upgrade",
		Aliases: []string{"update", "up"},
		Short:   "upgrade NixOS system",
		Long:    "Small wrapper around nixos-rebuild to upgrade NixOS system from current infra git repo",
		RunE: func(cmd *cobra.Command, args []string) error {
			remote := sshConfig.Host != ""

			if len(overrideInputs) > 0 && !useLocalGitRepository {
				return errs.With("--input can only be used together with --git")
			}

			switch {
			case !remote && useLocalGitRepository:
				return upgradeLocalFromGit(action, systemName, overrideInputs)
			case !remote && !useLocalGitRepository:
				return upgradeLocalFromUpstream(action, systemName)
			case remote && useLocalGitRepository:
				return upgradeRemoteTargetHostFromGit(&sshConfig, action, systemName, overrideInputs)
			case remote && !useLocalGitRepository:
				return upgradeRemoteFromUpstream(&sshConfig, action, systemName)
			default:
				return errs.With("Unsupported update case")
			}
		},
	}

	cmd.Flags().StringVarP(&action, "action", "a", "switch", "nixos-rebuild action to perform (switch, boot, test, build, reboot). reboot switches the boot configuration then reboots the host")
	cmd.Flags().StringVarP(&systemName, "system-name", "n", "", "nixos system name to apply. If not provided, will use the current system name. Useful when renaming system")
	cmd.Flags().BoolVar(&useLocalGitRepository, "git", false, "use current local git repository state instead of upstream repository")
	cmd.Flags().StringArrayVar(&overrideInputs, "input", nil, "override a flake input, format name=value (e.g. bcl-override1=path:/home/n0rad/Perso/bcl/becloudless/nixos). Can be repeated. Only valid with --git")
	flags.WithSSHRemoteFlags(cmd, &sshConfig)

	return cmd
}

// buildOverrideInputArgs converts "name=value" override strings into nixos-rebuild/nix
// "--override-input name value" argument pairs.
func buildOverrideInputArgs(overrideInputs []string) ([]string, error) {
	args := make([]string, 0, len(overrideInputs)*3)
	for _, override := range overrideInputs {
		name, value, found := strings.Cut(override, "=")
		if !found || name == "" || value == "" {
			return nil, errs.WithF(data.WithField("input", override), "Invalid --input, expected format name=value")
		}
		args = append(args, "--override-input", name, value)
	}
	return args, nil
}

// listFlakeInputNames returns the names of a local flake's top-level inputs, as declared in its
// flake.lock, by reading `nix flake metadata --json`.
func listFlakeInputNames(flakeDir string) ([]string, error) {
	output, err := runner.NewLocalRunner().ExecCmdGetStdout("nix", "flake", "metadata", "--json", flakeDir)
	if err != nil {
		return nil, errs.WithEF(err, data.WithField("flake", flakeDir), "Failed to read flake metadata")
	}

	var metadata struct {
		Locks struct {
			Root  string `json:"root"`
			Nodes map[string]struct {
				Inputs map[string]json.RawMessage `json:"inputs"`
			} `json:"nodes"`
		} `json:"locks"`
	}
	if err := json.Unmarshal([]byte(output), &metadata); err != nil {
		return nil, errs.WithE(err, "Failed to parse flake metadata")
	}

	rootNode, ok := metadata.Locks.Nodes[metadata.Locks.Root]
	if !ok {
		return nil, errs.With("Flake metadata is missing its root lock node")
	}

	names := make([]string, 0, len(rootNode.Inputs))
	for name := range rootNode.Inputs {
		names = append(names, name)
	}
	sort.Strings(names)
	return names, nil
}

// validateOverrideInputs ensures every overridden input (given as "name=value") is actually declared
// by the target flake, failing with the list of available input names otherwise.
func validateOverrideInputs(flakeDir string, overrideInputs []string) error {
	if len(overrideInputs) == 0 {
		return nil
	}

	available, err := listFlakeInputNames(flakeDir)
	if err != nil {
		return err
	}
	availableSet := make(map[string]bool, len(available))
	for _, name := range available {
		availableSet[name] = true
	}

	for _, override := range overrideInputs {
		name, _, _ := strings.Cut(override, "=")
		if !availableSet[name] {
			return errs.WithF(data.WithField("input", name).WithField("available", strings.Join(available, ", ")),
				"Unknown flake input, it is not declared by the target flake")
		}
	}
	return nil
}

// upgradeLocalFromGit rebuilds the current (local) system from the local infra git repository state.
func upgradeLocalFromGit(action string, systemName string, overrideInputs []string) error {
	logs.WithField("repo", bcl.BCL.System.Repository).Info("Update current system using local git repository state")

	repository, err := openLocalInfraRepository()
	if err != nil {
		return err
	}

	flakeDir := filepath.Join(repository.Root, "nixos")
	if err := validateOverrideInputs(flakeDir, overrideInputs); err != nil {
		return err
	}
	overrideInputArgs, err := buildOverrideInputArgs(overrideInputs)
	if err != nil {
		return err
	}

	run, err := localRunner(true)
	if err != nil {
		return err
	}

	args := append([]string{nixosRebuildAction(action), "--flake", buildFlakeTarget(flakeDir, systemName), "--no-write-lock-file"}, overrideInputArgs...)
	if err := run.ExecCmd("nixos-rebuild", args...); err != nil {
		return err
	}
	return rebootIfRequested(run, action)
}

// upgradeLocalFromUpstream rebuilds the current (local) system from the configured upstream repository.
func upgradeLocalFromUpstream(action string, systemName string) error {
	logs.WithField("repo", bcl.BCL.System.Repository).Info("Update current system using upstream state")

	run, err := localRunner(true)
	if err != nil {
		return err
	}

	if err := run.ExecCmd("nixos-rebuild", nixosRebuildAction(action), "--flake", buildFlakeTarget(bcl.BCL.System.Repository, systemName),
		"--no-write-lock-file", "--refresh", "--upgrade"); err != nil {
		return err
	}
	return rebootIfRequested(run, action)
}

// upgradeRemoteTargetHostFromGit builds locally from the local infra git repository state and deploys to a
// remote host via nixos-rebuild's --target-host/--use-remote-sudo.
func upgradeRemoteTargetHostFromGit(sshConfig *runner.SshConnectionConfig, action string, systemName string, overrideInputs []string) error {
	logs.WithField("repo", bcl.BCL.System.Repository).Info("Update remote system using local git repository state")

	repository, err := openLocalInfraRepository()
	if err != nil {
		return err
	}

	flakeDir := filepath.Join(repository.Root, "nixos")
	if err := validateOverrideInputs(flakeDir, overrideInputs); err != nil {
		return err
	}
	overrideInputArgs, err := buildOverrideInputArgs(overrideInputs)
	if err != nil {
		return err
	}

	run, err := localRunner(false)
	if err != nil {
		return err
	}

	args := append([]string{nixosRebuildAction(action), "--flake", buildFlakeTarget(flakeDir, systemName),
		"--target-host", sshTargetHost(sshConfig), "--use-remote-sudo", "--no-write-lock-file"}, overrideInputArgs...)
	if err := run.ExecCmd("nixos-rebuild", args...); err != nil {
		return err
	}

	if action != "reboot" {
		return nil
	}

	sshRun, err := runner.NewSshRunner(sshConfig)
	if err != nil {
		return errs.WithE(err, "Failed to create SSH runner to reboot remote host")
	}
	sudoRun, err := runner.NewSudoRunner(sshRun)
	if err != nil {
		return errs.WithE(err, "Failed to create remote sudo runner to reboot remote host")
	}
	logs.WithField("host", sshTargetHost(sshConfig)).Info("Rebooting remote system")
	return sudoRun.ExecCmd("reboot")
}

// upgradeRemoteFromUpstream connects to a remote host over SSH and rebuilds it there, using the upstream
// repository configured in that remote host's own system config.
func upgradeRemoteFromUpstream(sshConfig *runner.SshConnectionConfig, action string, systemName string) error {
	logs.WithField("repo", bcl.BCL.System.Repository).WithField("host", sshConfig.Host).Info("Update remote host using upstream state")

	run, err := runner.NewSshRunner(sshConfig)
	if err != nil {
		return errs.WithE(err, "Failed to create SSH runner")
	}
	config, err := getSystemConfigFromRemoteSystem(run)
	if err != nil {
		return errs.WithE(err, "Failed to get system config from remote system")
	}

	sudoRun, err := runner.NewSudoRunner(run)
	if err != nil {
		return errs.WithE(err, "Failed to create remote sudo runner")
	}
	if err := sudoRun.ExecCmd("nixos-rebuild", nixosRebuildAction(action), "--flake", buildFlakeTarget(config.Repository, systemName),
		"--no-write-lock-file", "--refresh", "--upgrade"); err != nil {
		return err
	}
	return rebootIfRequested(sudoRun, action)
}

// nixosRebuildAction translates the meta "reboot" action (switch boot config, then reboot) into the
// actual nixos-rebuild action to run.
func nixosRebuildAction(action string) string {
	if action == "reboot" {
		return "boot"
	}
	return action
}

// rebootIfRequested reboots the host via run when the requested action is the meta "reboot" action.
func rebootIfRequested(run runner.Runner, action string) error {
	if action != "reboot" {
		return nil
	}
	logs.Info("Rebooting system")
	return run.ExecCmd("reboot")
}

// openLocalInfraRepository opens the git repository at the current directory and stages all changes,
// since the nix build process only picks up files that are in git state.
func openLocalInfraRepository() (*bclGit.Repository, error) {
	repository, err := bclGit.OpenRepository(".")
	if errs.Is(err, git.ErrRepositoryNotExists) {
		return nil, errs.With("Not an infra folder")
	} else if err != nil {
		return nil, errs.WithE(err, "Failed to open git repository")
	}

	if err := repository.AddAll(); err != nil {
		return nil, errs.WithE(err, "failed to add changes to git")
	}
	return repository, nil
}

// localRunner returns a runner for the local system, wrapped with sudo when withSudo is true and the
// current process isn't already running as root.
func localRunner(withSudo bool) (runner.Runner, error) {
	var run runner.Runner = runner.NewLocalRunner()
	if withSudo && os.Geteuid() != 0 {
		sudoRun, err := runner.NewSudoRunner(run)
		if err != nil {
			return nil, errs.WithE(err, "Failed to create sudo runner")
		}
		run = sudoRun
	}
	return run, nil
}

// sshTargetHost formats the SSH connection config as a nixos-rebuild --target-host argument (user@host).
func sshTargetHost(sshConfig *runner.SshConnectionConfig) string {
	if sshConfig.User != "" {
		return sshConfig.User + "@" + sshConfig.Host
	}
	return sshConfig.Host
}

func getSystemConfigFromRemoteSystem(run runner.Runner) (*bcl.SystemConfig, error) {
	if _, err := run.ExecCmdGetStdout("test", "-f", bcl.PathSystemConfig); err != nil {
		return nil, errs.WithEF(err, data.WithField("path", bcl.PathSystemConfig), "Remote system config file does not exist. Please create it on the target host")
	}

	output, err := run.ExecCmdGetStdout("cat", bcl.PathSystemConfig)
	if err != nil {
		return nil, errs.WithE(err, "Failed to read remote system config")
	}

	config, err := bcl.LoadSystemConfigFromBytes([]byte(output))
	if err != nil {
		return nil, errs.WithE(err, "Failed to parse remote system config")
	}

	return config, nil
}
