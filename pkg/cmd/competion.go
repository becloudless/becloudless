package cmd

import (
	"fmt"
	"os"

	"github.com/n0rad/go-erlog/data"
	"github.com/n0rad/go-erlog/errs"
	"github.com/spf13/cobra"
)

func completionCmd() *cobra.Command {
	cmd := &cobra.Command{
		Use:   "completion bash|zsh|fish",
		Short: "Generates shell completion",
		Args:  cobra.ExactArgs(1),
		Long: fmt.Sprintf(`Generate bcl completion.
To load completion run one of the next command in you shell config:
source <(%s completion bash)
source <(%s completion zsh)
%s completion fish | source
`, os.Args[0], os.Args[0], os.Args[0]),
		RunE: func(cmd *cobra.Command, args []string) error {
			switch args[0] {
			case "bash":
				return cmd.Root().GenBashCompletionV2(os.Stdout, true)
			case "fish":
				return cmd.Root().GenFishCompletion(os.Stdout, true)
			case "zsh":
				return cmd.Root().GenZshCompletion(os.Stdout)
			default:
				return errs.WithF(data.WithField("type", args[0]), "Unknown completion type")
			}
		},
	}

	return cmd
}
