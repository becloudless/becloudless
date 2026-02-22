package nixos

import (
	"fmt"

	"github.com/becloudless/becloudless/pkg/bcl"
	"github.com/n0rad/go-erlog/errs"
	"github.com/spf13/cobra"
)

func nixosIsoSystemsCmd() *cobra.Command {
	return &cobra.Command{
		Use:     "systems",
		Aliases: []string{"system"},
		Short:   "List available systems",
		RunE: func(cmd *cobra.Command, args []string) error {
			infra, err := bcl.FindInfraFromPath(".")
			if err != nil {
				return errs.WithE(err, "Failed to open current infra repository")
			}

			systems, err := findAvailableSystems(infra.GetNixosDir())
			if err != nil {
				return errs.WithE(err, "Failed to list available systems")
			}

			for _, s := range systems {
				fmt.Println(s)
			}
			return nil
		},
	}
}
