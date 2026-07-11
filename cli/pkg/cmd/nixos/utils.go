package nixos

import (
	"github.com/n0rad/memguarded"
	"github.com/spf13/cobra"
)

func withSudoPasswordFlag(cmd *cobra.Command, service *memguarded.Service) {
	cmd.Flags().BoolFuncP("ask-sudo-password", "P", "ask sudo password", func(s string) error {
		return service.AskSecret(false, "Sudo password")
	})
}
