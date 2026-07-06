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

/*

nix-shell -p wakeonlan --run "wakeonlan 00:d8:61:6f:f8:6e"






*/
