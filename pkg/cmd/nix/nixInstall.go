package nix

import (
	"github.com/becloudless/becloudless/pkg/nix"
	"github.com/n0rad/go-erlog/errs"
	"github.com/n0rad/go-erlog/logs"
	"github.com/n0rad/memguarded"
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
			if err := nix.EnsureNixIsAvailable(); err != nil {
				return errs.WithE(err, "Nix install failed")
			}

			sudoPasswordService := memguarded.Service{}
			if askPassword {
				//TODO
				//if err := sudoPasswordService.AskSecret(false, "Sudo password on host to install? "); err != nil {
				//	return errs.WithE(err, "Failed to grab sudo password")
				//}
			}

			return nix.InstallAnywhere(host, user, &sudoPasswordService)

			//localRunner := runner.NewLocalRunner()
			//if err := localRunner.RunCommand("ls", "-la", "/"); err != nil {
			//	return err
			//}

			//sys := system.System{
			//	Runner: sshRunner,
			//}

			//available, required, err := sys.IsSudoAvailableAndPasswordRequired()
			//if !available {
			//	println("sudo is not available")
			//} else if required {
			//	println("sudo password is required")
			//} else {
			//	println("sudo password is not required")
			//}
			//return err

			//if err := sshRunner.RunCommand("ls", "-la", "/"); err != nil {
			//	return errs.WithE(err, "Command failed on remote")
			//}
			//
			//err := ssh.RemoteRun(user, , "", "ls -la / | grep a")
			//if err != nil {
			//	return err
			//}
		},
	}
	cmd.Flags().StringVarP(&host, "host", "h", "", "host ip to install")
	cmd.Flags().StringVarP(&user, "user", "u", "install", "user for the connection")
	cmd.Flags().BoolVarP(&askPassword, "ask-password", "P", false, "ask password")

	if err := cmd.MarkFlagRequired("host"); err != nil {
		logs.WithE(err).Fatal("failed")
	}
	return cmd
}
