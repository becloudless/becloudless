package version

import (
	"fmt"
	"github.com/becloudless/becloudless/pkg/bcl"
	"github.com/spf13/cobra"
	"runtime/debug"
)

func VersionCmd() *cobra.Command {
	var short bool
	cmd := &cobra.Command{
		Use: "version",
		RunE: func(cmd *cobra.Command, args []string) error {
			if short {
				fmt.Println(bcl.BCL.Version)
				return nil
			}

			fmt.Println("name:", bcl.BCL.Name)
			fmt.Println("version:", bcl.BCL.Version)
			fmt.Println("home:", bcl.BCL.Home)
			fmt.Println()

			info, _ := debug.ReadBuildInfo()
			fmt.Println("package.path:", info.Main.Path)
			fmt.Println("package.version:", info.Main.Version)
			fmt.Println("package.sum:", info.Main.Sum)
			for _, v := range info.Settings {
				fmt.Println("build."+v.Key+":", v.Value)
			}
			return nil
		},
	}
	cmd.Flags().BoolVarP(&short, "short", "s", false, "only version number")
	return cmd
}
