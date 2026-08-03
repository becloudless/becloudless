package nixos

import (
	"fmt"
	"os"
	"strings"

	"github.com/becloudless/becloudless/pkg/bcl"
	"github.com/becloudless/becloudless/pkg/system/runner"
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
					// repository, err := bclGit.OpenRepository(".")
					// if errs.Is(err, git.ErrRepositoryNotExists) {
					// 	logs.WithField("repo", bcl.BCL.System.Repository).Info("Not in an infra folder, updating using upstream git repository")

					// 	if bcl.BCL.System.Repository == "" {
					// 		return errs.With("No repository configured in bcl config")
					// 	}

					// } else if err != nil {
					// 	return errs.WithE(err, "failed to open git repository")
					// } else {
					// 	// Nix build process only files that are in git state
					// 	if err := repository.AddAll(); err != nil {
					// 		return errs.WithE(err, "failed to add changes to git")
					// 	}

					// 	run, err := runner.NewSudoRunner(runner.Runner(runner.NewLocalRunner()))
					// 	if err != nil {
					// 		return err
					// 	}
					// 	//if os.Geteuid() != 0 {
					// 	// Running sudo internally to prevent root modification of git state during add
					// 	//var password *memguarded.Service
					// 	//if err := runner.IsSudoRunnableWithoutPassword(run); err != nil {
					// 	//	password = memguarded.NewService()
					// 	//	if err := password.AskSecret(false, "Sudo password to run upgrade"); err != nil {
					// 	//		return errs.WithE(err, "Failed to get sudo password")
					// 	//	}
					// 	//}
					// 	//run, err = runner.NewSudoRunner(run)
					// 	//if err != nil {
					// 	//	return errs.WithE(err, "Failed to create sudo runner")
					// 	//}
					// 	//}

					// 	return run.ExecCmd("nixos-rebuild", action, "--flake", buildFlakeTarget(filepath.Join(repository.Root, "nixos"), systemName))
					return errs.With("not implemented")
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

			}
			return errs.With("Remote upgrade is not implemented yet")
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
