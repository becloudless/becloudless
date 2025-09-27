package docker

import (
	"github.com/spf13/cobra"
)

func BuildCmd() *cobra.Command {
	config := BuildConfig{
		Load: true,
	}
	cmd := &cobra.Command{
		Use:   "build",
		Args:  cobra.ExactArgs(0),
		Short: "Build a Docker image",
		RunE: func(cmd *cobra.Command, args []string) error {
			return dockerBuildx(config)
		},
	}

	cmd.Flags().BoolVar(&config.Cache, "cache", true, "use cache when building the image")
	AddBuildPushCommonFlags(cmd, &config)

	return cmd
}
