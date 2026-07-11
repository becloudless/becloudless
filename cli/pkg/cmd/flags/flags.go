package flags

import (
	"os"

	"github.com/becloudless/becloudless/pkg/system/runner"
	"github.com/spf13/cobra"
)

func WithSSHRemoteFlags(cmd *cobra.Command, sshConfig *runner.SshConnectionConfig) {
	cmd.Flags().StringVarP(&sshConfig.Host, "host", "h", "", "host to connect to")
	cmd.Flags().IntVarP(&sshConfig.Port, "port", "p", 22, "port")
	cmd.Flags().StringVarP(&sshConfig.User, "user", "u", os.Getenv("USER"), "user for the connection")
	cmd.Flags().StringVarP(&sshConfig.IdentifyFile, "identify", "i", "", "ssh private key file")
	cmd.Flags().BoolFuncP("ask-password", "P", "ask ssh password", func(s string) error {
		return sshConfig.Password.AskSecret(false, "SSH password")
	})
	cmd.Flags().BoolVarP(&sshConfig.InsecureHostKey, "insecure-host-key", "I", true, "Do not check host key")
}
