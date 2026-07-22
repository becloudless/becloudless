package backup

import (
	"github.com/becloudless/becloudless/pkg/nixos"
	"github.com/n0rad/go-erlog/errs"
	"github.com/spf13/cobra"
)

func nixosBackupUmountCmd() *cobra.Command {
	cmd := &cobra.Command{
		Use:     "umount <mountpoint>",
		Aliases: []string{"unmount"},
		Short:   "Unmount a backup previously mounted with 'backup mount'",
		Args:    cobra.ExactArgs(1),
		RunE: func(cmd *cobra.Command, args []string) error {
			if err := nixos.UmountBackup(args[0]); err != nil {
				return errs.WithE(err, "Failed to unmount backup")
			}
			return nil
		},
	}
	return cmd
}
