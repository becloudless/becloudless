package nixos

import (
	"os"
	"path/filepath"

	"github.com/becloudless/becloudless/pkg/git"
	"github.com/becloudless/becloudless/pkg/system/runner"
	"github.com/n0rad/go-erlog/errs"
	"github.com/spf13/cobra"
)

func nixosUpgradeCmd() *cobra.Command {
	var action string

	cmd := &cobra.Command{
		Use:   "upgrade",
		Short: "upgrade NixOS system",
		Long:  "Small wrapper around nixos-rebuild to upgrade NixOS system from current infra git repo",
		RunE: func(cmd *cobra.Command, args []string) error {
			if os.Geteuid() != 0 {
				return errs.With("Nixos upgrade must be run as root")
			}

			repository, err := git.OpenRepository(".")
			if err != nil {
				return errs.WithE(err, "failed to open git repository")
			}

			// Nix build process only files that are in git state
			if err := repository.AddAll(); err != nil {
				return errs.WithE(err, "failed to add changes to git")
			}

			localRunner := runner.NewLocalRunner()
			localRunner.ExecCmd("nixos-rebuild", action, "--flake", filepath.Join(repository.Root, "nixos"))

			return nil
		},
	}

	cmd.Flags().StringVarP(&action, "action", "a", "switch", "nixos-rebuild action to perform (switch, boot, test, build)")

	return cmd
}
