package backup

import (
	"io"
	"os"

	"github.com/becloudless/becloudless/pkg/nixos"
	"github.com/n0rad/go-erlog/errs"
	"github.com/n0rad/memguarded"
	"github.com/spf13/cobra"
)

func nixosBackupMountCmd() *cobra.Command {
	var identityFile string
	var sshUser string
	var rw bool
	identityService := memguarded.NewService()

	cmd := &cobra.Command{
		Use:   "mount <host:path> <mountpoint>",
		Short: "Mount a remote backup produced by bcl.backups",
		Long: "Mounts the remote encrypted backup directory via sshfs, then decrypts it with gocryptfs\n" +
			"using a passphrase derived from the ssh identity, the same way bcl.backups produced it.\n" +
			"Must be run on the host that produced the backup.\n" +
			"Mounted read-only unless --rw is passed.",
		Args: cobra.ExactArgs(2),
		RunE: func(cmd *cobra.Command, args []string) error {
			var identity io.Reader
			if identityService.IsSet() {
				identity = identityService.Reader()
			} else {
				file, err := os.Open(identityFile)
				if err != nil {
					return errs.WithE(err, "Failed to open identity file")
				}
				defer file.Close()
				identity = file
			}

			if err := nixos.MountBackup(args[0], args[1], identity, sshUser, rw); err != nil {
				return errs.WithE(err, "Failed to mount backup")
			}
			return nil
		},
	}

	cmd.Flags().StringVarP(&identityFile, "identity", "i", nixos.DefaultBackupIdentityFile, "ssh private key file used to reach the target and derive the decryption passphrase")
	cmd.Flags().StringVarP(&sshUser, "user", "u", "root", "ssh user used to connect to the target (ignored if the target already specifies a user@host)")
	cmd.Flags().BoolVar(&rw, "rw", false, "mount the backup read-write instead of read-only")
	cmd.Flags().BoolFuncP("ask-identity", "I", "read the ssh identity content (multiline) from a secured prompt instead of --identity", func(s string) error {
		secret, err := readMultilineSecret("SSH identity key content")
		if err != nil {
			return err
		}
		return identityService.FromBytes(&secret)
	})
	return cmd
}
