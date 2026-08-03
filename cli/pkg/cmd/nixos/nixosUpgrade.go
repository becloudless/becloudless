package nixos

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"github.com/becloudless/becloudless/pkg/bcl"
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

	cmd := &cobra.Command{
		Use:     "upgrade",
		Aliases: []string{"update", "up"},
		Short:   "upgrade NixOS system",
		Long:    "Small wrapper around nixos-rebuild to upgrade NixOS system from current infra git repo",
		RunE: func(cmd *cobra.Command, args []string) error {
			if sshConfig.Host == "" {
				if useLocalGitRepository {
					logs.WithField("repo", bcl.BCL.System.Repository).Info("Update current system using local git repository state")

					repository, err := bclGit.OpenRepository(".")
					if errs.Is(err, git.ErrRepositoryNotExists) {
						return errs.With("Not an infra folder")
					} else if err != nil {
						return errs.WithE(err, "Failed to open git repository")
					}

					// Nix build process only files that are in git state
					if err := repository.AddAll(); err != nil {
						return errs.WithE(err, "failed to add changes to git")
					}

					var run runner.Runner = runner.NewLocalRunner()
					if os.Geteuid() != 0 {
						sudoRun, err := runner.NewSudoRunner(run)
						if err != nil {
							return errs.WithE(err, "Failed to create sudo runner")
						}
						run = sudoRun
					}

					return run.ExecCmd("nixos-rebuild", action, "--flake", buildFlakeTarget(filepath.Join(repository.Root, "nixos"), systemName))
				} else {
					logs.WithField("repo", bcl.BCL.System.Repository).Info("Update current system using upstream state")

					var run runner.Runner = runner.NewLocalRunner()
					if os.Geteuid() != 0 {
						sudoRun, err := runner.NewSudoRunner(run)
						if err != nil {
							return errs.WithE(err, "Failed to create sudo runner")
						}
						run = sudoRun
					}

					return run.ExecCmd("nixos-rebuild", action, "--flake", buildFlakeTarget(bcl.BCL.System.Repository, systemName))
				}

			} else {
				if useLocalGitRepository {
					logs.WithField("repo", bcl.BCL.System.Repository).Info("Update remote system using local git repository state")

					repository, err := bclGit.OpenRepository(".")
					if errs.Is(err, git.ErrRepositoryNotExists) {
						return errs.With("Not an infra folder")
					} else if err != nil {
						return errs.WithE(err, "Failed to open git repository")
					}

					// Nix build process only files that are in git state
					if err := repository.AddAll(); err != nil {
						return errs.WithE(err, "failed to add changes to git")
					}

					var run runner.Runner = runner.NewLocalRunner()
					targetHost := sshConfig.Host
					if sshConfig.User != "" {
						targetHost = sshConfig.User + "@" + sshConfig.Host
					}
					return run.ExecCmd("nixos-rebuild", action, "--flake", buildFlakeTarget(filepath.Join(repository.Root, "nixos"), systemName), "--target-host", targetHost, "--use-remote-sudo")

					// nixos-rebuild switch --flake .#salon-0 --target-host n0rad@192.168.43.33 --use-remote-sudo

					return nil
				} else {
					logs.WithField("repo", bcl.BCL.System.Repository).WithField("host", sshConfig.Host).Info("Update remote host using upstream state")
					run, err := runner.NewSshRunner(&sshConfig)
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
					return sudoRun.ExecCmd("nixos-rebuild", action, "--flake", buildFlakeTarget(config.Repository, systemName))
				}
			}
		},
	}

	cmd.Flags().StringVarP(&action, "action", "a", "switch", "nixos-rebuild action to perform (switch, boot, test, build)")
	cmd.Flags().StringVarP(&systemName, "system-name", "n", "", "nixos system name to apply. If not provided, will use the current system name. Useful when renaming system")
	cmd.Flags().BoolVar(&useLocalGitRepository, "git", false, "use current local git repository state instead of upstream repository")
	withSSHRemoteFlags(cmd, &sshConfig)

	// nixos-rebuild test --refresh --flake git+ssh://git@gitea.lmr.io/lmr/infra?dir=nixos#vm --upgrade
	// nixos-rebuild build-vm --flake .#nixosConfigurations.Olimpo.config.system.build.toplevel

	return cmd
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
