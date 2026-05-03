package kube

import (
	"encoding/base64"
	"encoding/json"
	"fmt"
	"os"
	"os/exec"

	"github.com/n0rad/go-erlog/data"
	"github.com/n0rad/go-erlog/errs"
	"github.com/spf13/cobra"

	"github.com/becloudless/becloudless/pkg/kube"
)

func kubeSecretExtractCmd() *cobra.Command {
	var namespace string
	var outputFormat string

	cmd := cobra.Command{
		Use:     "extract <secret-name>",
		Aliases: []string{"e"},
		Short:   "Extract and decode a Kubernetes secret's data fields",
		Args:    cobra.ExactArgs(1),
		RunE: func(cmd *cobra.Command, args []string) error {
			if outputFormat != "stdout" && outputFormat != "files" {
				return errs.WithF(data.WithField("output", outputFormat), "Invalid output format, must be 'stdout' or 'files'")
			}
			secretName := args[0]

			ctx, err := kube.GetContext(".")
			if err != nil {
				return errs.WithE(err, "Cannot find kube cluster context. Are you in a cluster folder?")
			}

			kubectlArgs := []string{"get", "secret", secretName, "-o", "json"}
			if namespace != "" {
				kubectlArgs = append(kubectlArgs, "-n", namespace)
			}

			getCmd := exec.Command("kubectl", kubectlArgs...)
			getCmd.Env = append(os.Environ(), fmt.Sprintf("KUBECONFIG=%s", ctx.KubeConfig))
			output, err := getCmd.CombinedOutput()
			if err != nil {
				return errs.WithEF(err, data.WithField("output", string(output)).WithField("secret", secretName), "Failed to get secret")
			}

			var secret struct {
				Data       map[string]string `json:"data"`
				StringData map[string]string `json:"stringData"`
			}
			if err := json.Unmarshal(output, &secret); err != nil {
				return errs.WithE(err, "Failed to parse secret JSON")
			}

			writeOrPrint := func(key, value string) error {
				if outputFormat == "files" {
					if err := os.WriteFile(key, []byte(value), 0o600); err != nil {
						return errs.WithEF(err, data.WithField("key", key), "Failed to write secret field to file")
					}
					fmt.Printf("wrote %s\n", key)
					return nil
				}
				fmt.Printf("%s : %s\n", key, value)
				return nil
			}

			for k, v := range secret.StringData {
				if err := writeOrPrint(k, v); err != nil {
					return err
				}
			}

			for k, v := range secret.Data {
				decoded, err := base64.StdEncoding.DecodeString(v)
				if err != nil {
					return errs.WithEF(err, data.WithField("key", k), "Failed to base64-decode secret field")
				}
				if err := writeOrPrint(k, string(decoded)); err != nil {
					return err
				}
			}

			return nil
		},
	}

	cmd.Flags().StringVarP(&namespace, "namespace", "n", "", "Kubernetes namespace of the secret")
	cmd.Flags().StringVarP(&outputFormat, "output", "o", "stdout", "Output format: stdout or files")

	return &cmd
}
