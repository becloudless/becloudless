package cmd

import (
	"github.com/becloudless/becloudless/pkg/ssh"
	"github.com/n0rad/go-erlog/logs"
	"github.com/spf13/cobra"
)

func NixInstallCmd() *cobra.Command {
	var host string
	var user string
	var askPassword bool
	cmd := &cobra.Command{
		Use:   "install",
		Short: "Install remote device",
		RunE: func(cmd *cobra.Command, args []string) error {
			err := ssh.RemoteRun(user, host, "", "ls -la / | grep a")
			if err != nil {
				return err
			}
			return nil
		},
	}
	cmd.Flags().StringVarP(&user, "user", "u", "install", "user for the connection")
	cmd.Flags().BoolVarP(&askPassword, "ask-password", "a", false, "ask password")

	cmd.Flags().StringVarP(&host, "host", "h", "", "host ip to install")
	if err := cmd.MarkFlagRequired("host"); err != nil {
		logs.WithE(err).Fatal("failed")
	}
	return cmd
}
