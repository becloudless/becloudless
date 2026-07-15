package backup

import (
	"github.com/spf13/cobra"
)

func NixosBackupCmd() *cobra.Command {
	cmd := &cobra.Command{
		Use:   "backup",
		Short: "Handle bcl.backups remote backups",
	}
	cmd.AddCommand(
		nixosBackupMountCmd(),
		nixosBackupUmountCmd(),
	)
	return cmd
}
