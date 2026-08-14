package iso

import (
	"os"
	"path/filepath"
	"strings"

	"github.com/becloudless/becloudless/pkg/bcl"
	"github.com/becloudless/becloudless/pkg/security"
	"github.com/becloudless/becloudless/pkg/system/runner"
	"github.com/n0rad/go-erlog/data"
	"github.com/n0rad/go-erlog/errs"
	"github.com/n0rad/go-erlog/logs"
	"github.com/spf13/cobra"
	"gopkg.in/yaml.v3"
)

func nixosIsoBuildCmd() *cobra.Command {
	var device string
	var typeAndSystem string
	var rebuild bool

	cmd := &cobra.Command{
		Use:   "build",
		Short: "Build iso image to boot device to install",
		RunE: func(cmd *cobra.Command, args []string) error {
			run := runner.NewLocalRunner()

			infra, err := bcl.FindInfraFromPath(".")
			if err != nil {
				return errs.WithE(err, "Failed to open current infra repository")
			}

			//nix eval --json ".#isoConfigurations" --apply 'x: builtins.attrNames x'

			var isoPath string
			typeAndSystemArray := strings.SplitN(typeAndSystem, "/", 2)
			if len(typeAndSystemArray) != 2 {
				return errs.WithF(data.WithField("system", typeAndSystem), "Invalid system type, expected format kind/system, e.g. iso/install or raw-efi/host")
			}
			switch typeAndSystemArray[0] {
			case "iso":
				isoPath = infra.GetNixosDir() + "/result/iso/bcl.iso"
			case "raw-efi":
				isoPath = infra.GetNixosDir() + "/result/nixos.img"
			}
			_, err = os.Stat(isoPath)
			if err != nil || rebuild {

				configAttr := infra.GetNixosDir() + "#" + typeAndSystemArray[0] + "Configurations." + typeAndSystemArray[1]

				logs.WithField("system", typeAndSystemArray[1]).Info("Checking if system requires a pre-generated ssh host key")
				enableSshHostKey, err := run.ExecCmdGetStdout(
					"nix",
					"--extra-experimental-features", "nix-command flakes",
					"eval", configAttr+".config.bcl.role.install.enableSshHostKey")
				if err != nil {
					return errs.WithE(err, "Failed to evaluate bcl.role.install.enableSshHostKey for system")
				}

				buildArgs := []string{"build", configAttr}
				var buildEnvs []string

				if enableSshHostKey == "true" {
					keyFile, err := os.CreateTemp("", "bcl-install-ssh-host-key-")
					if err != nil {
						return errs.WithE(err, "Failed to create temp file for install host key")
					}
					keyFilePath := keyFile.Name()
					keyFile.Close()
					defer func() {
						if err := os.Remove(keyFilePath); err != nil {
							logs.WithE(err).WithField("file", keyFilePath).Error("Failed to remove install host key temp file")
						}
					}()

					sopsFile := infra.GetNixosDir() + "/modules/nixos/groups/install/default.secrets.yaml"
					logs.WithField("file", sopsFile).Info("Extracting install host key from group")

					content, err := security.DecryptSopsYAMLWithAgeKey(sopsFile, "")
					if err != nil {
						return errs.WithE(err, "Failed to decrypt install group sops file")
					}

					// TODO standardize?
					secretData := struct {
						SshHostEd25519Key string `yaml:"ssh_host_ed25519_key"`
					}{}

					if err := yaml.Unmarshal(content, &secretData); err != nil {
						return errs.WithE(err, "Failed to parse install group secrets yaml")
					}

					if err := os.WriteFile(keyFilePath, []byte(secretData.SshHostEd25519Key), 0600); err != nil {
						return errs.WithEF(err, data.WithField("file", keyFilePath), "Failed to write install host key to temp file")
					}

					buildArgs = append(buildArgs, "--impure")
					buildEnvs = append(buildEnvs, "BCL_INSTALL_SSH_HOST_KEY_FILE="+keyFilePath)
				}

				logs.WithField("system", typeAndSystemArray[1]).Info("Building iso")

				// raw-efi is building the img on TMPDIR, which may be too small, using current folder
				dir, err := os.Getwd()
				if err != nil {
					return errs.WithE(err, "Failed to get current working directory")
				}
				currentTmp := filepath.Join(dir, "build_tmp")
				if err := os.MkdirAll(currentTmp, 0777); err != nil {
					return errs.WithE(err, "Failed to create temporary build directory")
				}
				if err := os.Setenv("TMPDIR", currentTmp); err != nil {
					return errs.WithE(err, "Failed to set TMPDIR environment variable")
				}
				defer func() {
					if err := os.RemoveAll(currentTmp); err != nil {
						logs.WithE(err).WithField("dir", currentTmp).Error("Failed to remove temporary build directory")
					}
				}()
				if _, err := run.Exec(&buildEnvs, os.Stdin, os.Stdout, os.Stderr, "nix", buildArgs...); err != nil {
					return errs.WithE(err, "Iso build failed")
				}
			}


			if device == "" {
				logs.WithField("path", isoPath).Info("Your iso is available")
				return nil
			}

			if _, err := os.Stat(device); err != nil {
				return errs.WithEF(err, data.WithField("device", device), "Target device does not exist or is not accessible")
			}

			sudoRun, err := runner.NewSudoRunner(run)
			if err != nil {
				return errs.WithE(err, "Failed to create sudo runner to write iso to device")
			}

			logs.WithField("device", device).Info("writing iso to device")
			if err := sudoRun.ExecCmd("dd", "if="+isoPath, "of="+device, "bs=4M", "status=progress", "oflag=sync"); err != nil {
				return errs.WithE(err, "Failed to write iso to device")
			}

			logs.Info("All good")
			return nil
		},
	}

	cmd.Flags().StringVarP(&typeAndSystem, "system", "s", "iso/install", "kind and target system configuration name")
	cmd.Flags().StringVarP(&device, "device", "d", "", "Target device to write the iso to")
	cmd.Flags().BoolVarP(&rebuild, "rebuild", "r", true, "Rebuild iso even if file is already available")

	_ = cmd.RegisterFlagCompletionFunc("system", func(cmd *cobra.Command, args []string, toComplete string) ([]string, cobra.ShellCompDirective) {
		infra, err := bcl.FindInfraFromPath(".")
		if err != nil {
			return nil, cobra.ShellCompDirectiveNoFileComp
		}
		systems, err := findAvailableSystems(infra.GetNixosDir())
		if err != nil {
			return nil, cobra.ShellCompDirectiveNoFileComp
		}
		return systems, cobra.ShellCompDirectiveNoFileComp
	})

	return cmd
}
