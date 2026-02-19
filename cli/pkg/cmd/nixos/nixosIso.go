package nixos

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
	"github.com/n0rad/memguarded"
	"github.com/spf13/cobra"
	"gopkg.in/yaml.v3"
)

// This matches the path used in the nixos install process
const InstallHostKeyTmpPath = "/tmp/install-ssh_host_ed25519_key"

func nixosIsoCmd() *cobra.Command {
	var device string
	var typeAndSystem string
	var rebuild bool

	sudoPassword := memguarded.NewService()
	cmd := &cobra.Command{
		Use:   "iso",
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

				if err := os.WriteFile(InstallHostKeyTmpPath, []byte(secretData.SshHostEd25519Key), 0600); err != nil {
					return errs.WithEF(err, data.WithField("file", InstallHostKeyTmpPath), "Failed to write install host key to temp file")
				}
				defer func() {
					if err := os.Remove(InstallHostKeyTmpPath); err != nil {
						logs.WithE(err).WithField("file", InstallHostKeyTmpPath).Error("Failed to remove install host key temp file")
					}
				}()

				logs.WithField("group", "install").Info("Building iso")

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
				if err := run.ExecCmd("nix", "build", infra.GetNixosDir()+"#"+typeAndSystemArray[0]+"Configurations."+typeAndSystemArray[1], "--impure"); err != nil {
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

			sudoRun, err := runner.NewSudoRunner(run, sudoPassword)
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
	cmd.Flags().BoolVarP(&rebuild, "rebuild", "r", false, "Rebuild iso even if file is already available")

	withSudoPasswordFlag(cmd, sudoPassword)

	return cmd
}

func findSystemKind() {

}
