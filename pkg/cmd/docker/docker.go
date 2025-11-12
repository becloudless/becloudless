package docker

import (
	"fmt"
	"github.com/becloudless/becloudless/pkg/docker"
	"github.com/becloudless/becloudless/pkg/system/runner"
	"github.com/becloudless/becloudless/pkg/version"
	"github.com/n0rad/go-erlog/data"
	"github.com/n0rad/go-erlog/errs"
	"github.com/n0rad/go-erlog/logs"
	"github.com/spf13/cobra"
	"os"
	"os/exec"
	"path"
	"path/filepath"
	"strings"
)

func DockerCmd() *cobra.Command {
	cmd := cobra.Command{
		Use:     "docker",
		Aliases: []string{"dk"},
	}
	cmd.AddCommand(
		BuildCmd(),
		PushCmd(),
	)
	return &cmd
}

func AddBuildPushCommonFlags(cmd *cobra.Command, config *BuildConfig) {
	cmd.Flags().BoolVar(&config.Git, "git", false, "Build from git status instead of path")
	cmd.Flags().StringVar(&config.GitRef, "git-ref", "", "Specify a git ref (branch, tag, commit) to build from when --git is set")
	cmd.Flags().StringVar(&config.Path, "path", ".", "Dockerfile or folder of dockerfile path")
	cmd.Flags().StringVar(&config.Platforms, "platforms", "linux/amd64,linux/arm64", "Comma-separated list of target platforms (e.g., linux/amd64,linux/arm64). If not set, it will be auto-detected from the Dockerfile or default to linux/amd64,linux/arm64")
	cmd.Flags().StringVar(&config.Registry, "registry", "gitea.cloudless.be", "Docker registry URL") // TODO
	cmd.Flags().StringVar(&config.Namespace, "namespace", "bcl", "Registry namespace")               // TODO
	cmd.Flags().StringVar(&config.BuildxFlags, "buildx-flags", "", "Additional flags to pass to docker buildx")
	cmd.Flags().BoolVar(&config.Load, "load", true, "Load the built image to local Docker daemon")
}

func validatePrerequisites() error {
	// Check if docker is available
	if err := exec.Command("docker", "--version").Run(); err != nil {
		return errs.WithE(err, "docker is not available")
	}

	// Check if docker buildx is available
	if err := exec.Command("docker", "buildx", "version").Run(); err != nil {
		return errs.WithE(err, "docker buildx is not available")
	}

	return nil
}

type BuildConfig struct {
	Path           string
	BuildPath      string
	DockerfilePath string
	Push           bool
	Load           bool
	Cache          bool
	BuildxFlags    string
	Registry       string
	Namespace      string
	Platforms      string
	Git            bool
	GitRef         string
}

// dockerBuild uses cmd to trigger docker because we need buildx, and it's not simple to do it in pure go
func dockerBuildx(config BuildConfig) error {
	if err := validatePrerequisites(); err != nil {
		return err
	}

	if stat, err := os.Stat(config.Path); err != nil {
		return errs.WithEF(err, data.WithField("path", config.Path), "Failed to read path")
	} else if stat.IsDir() {
		config.BuildPath = config.Path
		config.DockerfilePath = path.Join(config.Path, "Dockerfile")
	} else {
		config.BuildPath = filepath.Dir(config.Path)
		config.DockerfilePath = config.Path
	}

	args := []string{"buildx", "build", "--progress=plain"}

	if !config.Cache {
		args = append(args, "--no-cache")
	}

	if config.Platforms == "" {
		platforms, err := docker.ExtractPlatformFromDockerfile(filepath.Join(config.DockerfilePath, "Dockerfile"))
		if err != nil {
			return errs.WithE(err, "Failed to extract platform from Dockerfile")
		}
		config.Platforms = platforms
	}

	if config.Platforms != "" {
		args = append(args, "--platform="+config.Platforms)
	}

	tag, err := version.GenerateVersionFromDateAndGitState(1, config.DockerfilePath)
	if err != nil {
		return err
	}

	imageName, err := getFolderNameFromDockerfilePath(config.DockerfilePath)
	if err != nil {
		return err
	}

	fullImageName := fmt.Sprintf("%s/%s/%s", config.Registry, config.Namespace, imageName)
	args = append(args, "-t", fullImageName+":"+tag)
	args = append(args, "-t", fullImageName+":latest")

	args = append(args, "--build-arg=TAG="+tag)

	if config.BuildxFlags != "" {
		flagArgs := strings.Fields(config.BuildxFlags)
		args = append(args, flagArgs...)
	}

	if config.Push {
		args = append(args, "--push")
	}
	if config.Load {
		args = append(args, "--load")
	}

	args = append(args, "-f", config.DockerfilePath)
	args = append(args, config.BuildPath)

	logs.WithField("args", strings.Join(args, " ")).Debug("Executing docker buildx command")

	localRunner := runner.NewLocalRunner()
	return localRunner.ExecCmd("docker", args...)
}

func getFolderNameFromDockerfilePath(dockerfilePath string) (string, error) {
	path := filepath.Dir(dockerfilePath)
	abs, err := filepath.Abs(path)
	if err != nil {
		return "", err
	}
	info, err := os.Stat(abs)
	if err != nil {
		return "", err
	}
	if !info.IsDir() {
		return "", errs.WithEF(err, data.WithField("path", abs), "path is not a directory")
	}
	return filepath.Base(abs), nil
}
