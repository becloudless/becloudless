package docker

import (
	"fmt"
	"os"
	"os/exec"
	"path"
	"path/filepath"
	"strings"

	"github.com/becloudless/becloudless/pkg/docker"
	"github.com/becloudless/becloudless/pkg/git"
	"github.com/becloudless/becloudless/pkg/system/runner"
	"github.com/becloudless/becloudless/pkg/version"
	"github.com/n0rad/go-erlog/data"
	"github.com/n0rad/go-erlog/errs"
	"github.com/n0rad/go-erlog/logs"
	"github.com/spf13/cobra"
)

func DockerCmd() *cobra.Command {
	cmd := cobra.Command{
		Use:     "docker",
		Aliases: []string{"dk"},
	}
	cmd.AddCommand(
		buildCmd(),
		pushCmd(),
	)
	return &cmd
}

func AddBuildPushCommonFlags(cmd *cobra.Command, config *BuildConfig) {
	cmd.Flags().StringVar(&config.DockerfilePath, "path", ".", "Dockerfile or folder of Dockerfile path")
	cmd.Flags().StringVar(&config.Platforms, "platforms", "", "Comma-separated list of target platforms (e.g., linux/amd64,linux/arm64). If not set, it will be auto-detected from the Dockerfile or default to linux/amd64,linux/arm64")
	cmd.Flags().StringVar(&config.Repository, "repository", "", "Docker image repository URL. Will be deduced from git repo by default")
	cmd.Flags().StringVar(&config.Namespace, "namespace", "", "repository namespace") // TODO
	cmd.Flags().StringVar(&config.BuildxFlags, "buildx-flags", "", "Additional flags to pass to docker buildx")
	cmd.Flags().BoolVar(&config.Load, "load", true, "Load the built image to local Docker daemon")
}

func findDockerRepositoryFromGitRepository(path string) (string, error) {
	gitRepo, err := git.OpenRepository(path)
	if err != nil {
		return "", errs.WithE(err, "Failed to open git repository")
	}
	url, err := gitRepo.GetRemoteOriginURL()
	if err != nil {
		return "", errs.WithE(err, "Failed to get remote origin URL")
	}

	_, repository, err := docker.GetRegistryAndRepositoryFromGitUrl(url)
	if err != nil {
		return "", errs.WithE(err, "Failed to deduce registry from git URL")
	}

	return repository, nil
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
	DockerfilePath string
	BuildPath      string
	//DockerfilePath string
	Push        bool
	Load        bool
	Cache       bool
	BuildxFlags string
	Repository  string
	Name        string
	Namespace   string
	Platforms   string
	Tag         string
}

func (b *BuildConfig) Init() error {
	if stat, err := os.Stat(b.DockerfilePath); err != nil {
		return errs.WithEF(err, data.WithField("path", b.DockerfilePath), "Failed to read path")
	} else if stat.IsDir() {
		b.DockerfilePath = path.Join(b.DockerfilePath, "Dockerfile")
	} else {
		b.BuildPath = filepath.Dir(b.DockerfilePath)
	}

	if b.Repository == "" {
		repository, err := findDockerRepositoryFromGitRepository(b.DockerfilePath)
		if err != nil {
			if b.Push {
				return errs.WithE(err, "Cannot push, Failed to deduce docker repository")
			} else {
				logs.WithE(err).Warn("Failed to deduce docker repository. Would not be able to push")
			}
		}
		b.Repository = repository
	}

	fromDockerfile, err := docker.ExtractLabelsFromDockerfile(b.DockerfilePath)
	if err != nil {
		return errs.WithEF(err, data.WithField("dockerfile", b.DockerfilePath), "Failed to prepare build config from Dockerfile")
	}

	if b.Platforms == "" {
		if platforms, ok := fromDockerfile["platforms"]; ok {
			b.Platforms = platforms
		} else {
			b.Platforms = "linux/amd64,linux/arm64"
		}
	}

	if b.Tag == "" {
		tag, err := version.GenerateVersionFromDateAndGitState(1, b.DockerfilePath)
		if err != nil {
			return err
		}
		b.Tag = tag
	}

	if b.Name == "" {
		b.Name = filepath.Base(filepath.Dir(b.DockerfilePath))
	}

	if b.BuildPath == "" {
		b.BuildPath = filepath.Dir(b.DockerfilePath)
	}

	return nil
}

// dockerBuild uses cmd to trigger docker because we need buildx, and it's not simple to do it in pure go
func DockerBuildx(config BuildConfig) error {
	if err := validatePrerequisites(); err != nil {
		return err
	}

	args := []string{"buildx", "build", "--progress=plain"}

	if !config.Cache {
		args = append(args, "--no-cache")
	}

	if config.Platforms != "" {
		args = append(args, "--platform="+config.Platforms)
	}

	fullImageName := fmt.Sprintf("%s/%s", config.Repository, config.Name)
	if config.Namespace != "" {
		fullImageName = fmt.Sprintf("%s/%s/%s", config.Repository, config.Namespace, config.Name)
	}
	args = append(args, "-t", fullImageName+":"+config.Tag)
	args = append(args, "-t", fullImageName+":latest")

	args = append(args, "--build-arg=TAG="+config.Tag)

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

	localRunner := runner.NewLocalRunner()
	return localRunner.ExecCmd("docker", args...)
}
