package nixos

import (
	"os"
	"path/filepath"

	"github.com/becloudless/becloudless/pkg/git"
	"github.com/becloudless/becloudless/pkg/system/runner"
	"github.com/n0rad/go-erlog/errs"
	"github.com/n0rad/memguarded"
	"github.com/spf13/cobra"
)

func nixosUpgradeCmd() *cobra.Command {
	var action string

	cmd := &cobra.Command{
		Use:   "upgrade",
		Short: "upgrade NixOS system",
		Long:  "Small wrapper around nixos-rebuild to upgrade NixOS system from current infra git repo",
		RunE: func(cmd *cobra.Command, args []string) error {
			repository, err := git.OpenRepository(".")
			if err != nil {
				return errs.WithE(err, "failed to open git repository")
			}

			// Nix build process only files that are in git state
			if err := repository.AddAll(); err != nil {
				return errs.WithE(err, "failed to add changes to git")
			}

			run := runner.Runner(runner.NewLocalRunner())
			if os.Geteuid() != 0 {
				// Running sudo internally to prevent root modification of git state during add
				var password *memguarded.Service
				if err := runner.IsSudoRunnableWithoutPassword(run); err != nil {
					password = memguarded.NewService()
					if err := password.AskSecret(false, "Sudo password to run upgrade"); err != nil {
						return errs.WithE(err, "Failed to get sudo password")
					}
				}
				run, err = runner.NewSudoRunner(run, password)
				if err != nil {
					return errs.WithE(err, "Failed to create sudo runner")
				}
			}

			return run.ExecCmd("nixos-rebuild", action, "--flake", filepath.Join(repository.Root, "nixos"))
		},
	}

	cmd.Flags().StringVarP(&action, "action", "a", "switch", "nixos-rebuild action to perform (switch, boot, test, build)")

	// nixos-rebuild test --refresh --flake git+ssh://git@gitea.lmr.io/lmr/infra?dir=nixos#vm --upgrade
	// nixos-rebuild build-vm --flake .#nixosConfigurations.Olimpo.config.system.build.toplevel

	return cmd
}
