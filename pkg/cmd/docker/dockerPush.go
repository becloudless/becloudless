package docker

import "github.com/spf13/cobra"

func PushCmd() *cobra.Command {
	config := BuildConfig{
		Push:  true,
		Cache: false,
	}
	cmd := &cobra.Command{
		Use:   "push",
		Args:  cobra.ExactArgs(0),
		Short: "Build and push a Docker image from the current directory.",
		RunE: func(cmd *cobra.Command, args []string) error {
			return dockerBuildx(config)
		},
	}

	AddBuildPushCommonFlags(cmd, &config)

	return cmd
}
