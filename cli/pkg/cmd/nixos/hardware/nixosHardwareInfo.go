package hardware

import (
	"encoding/json"
	"fmt"
	"os"
	"regexp"

	"github.com/becloudless/becloudless/pkg/cmd/flags"
	"github.com/becloudless/becloudless/pkg/nixos"
	"github.com/becloudless/becloudless/pkg/system"
	"github.com/becloudless/becloudless/pkg/system/runner"
	"github.com/n0rad/go-erlog/data"
	"github.com/n0rad/go-erlog/errs"
	"github.com/n0rad/memguarded"
	"github.com/spf13/cobra"
	"golang.org/x/term"
	"gopkg.in/yaml.v3"
)

var yamlKeyPattern = regexp.MustCompile(`(?m)^(\s*(?:- )?)([\w.\-]+):(\s|$)`)

// boldYamlKeys wraps each yaml map key in ANSI bold codes, for nicer
// readability when printed to an interactive terminal.
func boldYamlKeys(yamlOut []byte) string {
	return yamlKeyPattern.ReplaceAllString(string(yamlOut), "$1\033[1m$2\033[0m:$3")
}

func nixosHardwareInfoCmd() *cobra.Command {

	sshConfig := runner.SshConnectionConfig{
		Password: memguarded.NewService(),
	}
	var outputFormat string

	cmd := &cobra.Command{
		Use:   "info",
		Short: "Dump system info",
		RunE: func(cmd *cobra.Command, args []string) error {
			var run runner.Runner = runner.NewLocalRunner()
			if sshConfig.Host != "" {
				sshRun, err := runner.NewSshRunner(&sshConfig)
				if err != nil {
					return errs.WithE(err, "Failed to connect to remote host")
				}

				run = sshRun
				if sshConfig.User != "root" {
					sudoRun, err := runner.NewSudoRunnerWithPassword(sshRun, sshConfig.Password)
					if err != nil {
						return errs.WithE(err, "Sudo cannot be run successfully on remote host")
					}
					run = sudoRun.WithInline(true)
				}
			}

			sys := system.System{
				SudoRunner: runner.NewShellRunner(run),
			}

			info, err := nixos.ExtractSystemInfo(sys)
			if err != nil {
				return errs.WithE(err, "Failed to extract system info")
			}

			switch outputFormat {
			case "yaml":
				out, err := yaml.Marshal(info)
				if err != nil {
					return errs.WithE(err, "Failed to marshal system info")
				}
				if term.IsTerminal(int(os.Stdout.Fd())) {
					fmt.Print(boldYamlKeys(out))
				} else {
					fmt.Print(string(out))
				}
			case "json":
				out, err := json.MarshalIndent(info, "", "  ")
				if err != nil {
					return errs.WithE(err, "Failed to marshal system info")
				}
				fmt.Println(string(out))
			default:
				return errs.WithF(data.WithField("output", outputFormat), "Invalid output format, must be 'json' or 'yaml'")
			}
			return nil
		},
	}

	flags.WithSSHRemoteFlags(cmd, &sshConfig)
	cmd.Flags().StringVarP(&outputFormat, "output", "o", "yaml", "Output format: json or yaml")

	return cmd
}
