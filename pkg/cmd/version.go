package cmd

import (
	"github.com/spf13/cobra"
	"runtime/debug"
)

func VersionCmd() *cobra.Command {
	cmd := &cobra.Command{
		Use: "version",
		RunE: func(cmd *cobra.Command, args []string) error {
			info, _ := debug.ReadBuildInfo()
			println(info.Path)
			println(info.Main.Version)
			println(info.Main.Sum)
			println(info.Main.Path)
			for _, v := range info.Settings {
				println(v.Key, " = ", v.Value)
			}
			return nil
		},
	}
	return cmd
}
