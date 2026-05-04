package terraform

import (
	"bytes"
	"os"
	"path/filepath"

	"github.com/becloudless/becloudless/pkg/bcl"
	"github.com/becloudless/becloudless/pkg/system/runner"
	"github.com/hashicorp/go-version"
	"github.com/n0rad/go-erlog/data"
	"github.com/n0rad/go-erlog/errs"
	"github.com/n0rad/go-erlog/logs"
)

// renovate: datasource=github-releases depName=hashicorp/terraform
const terraformDefaultVersion = "1.15.1"
const terraformBinPath = "terraform-bin"

type Client struct {
	binDir          string
	version         *version.Version
	localBinaryPath string
	planfile        string
	runner          runner.Runner
}

func NewClient(wantedVersion *version.Version) (*Client, error) {
	v := wantedVersion
	if v == nil {
		vDefault, err := version.NewVersion(terraformDefaultVersion)
		if err != nil {
			return nil, errs.WithE(err, "Failed to create terraform default version")
		}
		v = vDefault
	}

	client := Client{
		version: v,
		binDir:  filepath.Join(bcl.BCL.CacheFolder, terraformBinPath),
		runner:  runner.NewLocalRunner(),
	}

	if _, err := client.ensureVersion(client.version); err != nil {
		return nil, errs.WithEF(err, data.WithField("version", client.version), "Failed to ensure terraform version is available")
	}
	return &client, nil
}

func (c *Client) Close() {
	if c.planfile != "" {
		os.Remove(c.planfile)
	}
}

func (c *Client) RunInit(projectPath string) error {
	logs.WithField("project", projectPath).Info("Running terraform init")
	stderr, err := c.runner.ExecCmdGetStderr(
		c.localBinaryPath,
		"-chdir="+projectPath,
		"init",
		"-input=false",
		"-no-color",
	)
	if err != nil {
		return errs.WithEF(err, data.WithField("stderr", stderr).WithField("path", projectPath), "Init failed")
	}
	return nil
}

type PlanResult int

const (
	PlanNoDiff = iota
	PlanError
	PlanDiff
	PlanUnknown
)

func (c *Client) RunPlan(projectPath string) (PlanResult, error) {
	file, err := os.CreateTemp("", "bcl-terraform-"+filepath.Base(projectPath)+".*.plan")
	if err != nil {
		return PlanUnknown, errs.WithE(err, "Failed to create temp plan file")
	}
	file.Close()
	defer os.Remove(file.Name())

	c.planfile = file.Name()

	logs.WithField("project", projectPath).Info("Running terraform plan")
	var stderr bytes.Buffer
	i, err := c.runner.Exec(nil, os.Stdin, os.Stdout, os.Stderr,
		c.localBinaryPath,
		"-chdir="+projectPath,
		"plan",
		"-detailed-exitcode",
		"-input=false",
		"-lock=false",
		"-no-color",
		"-out="+c.planfile,
	)
	switch i {
	case PlanNoDiff:
		logs.WithField("project", projectPath).Debug("Plan result with empty diff")
		return PlanNoDiff, nil
	case PlanError:
		return PlanError, errs.WithEF(err, data.WithField("project", projectPath).WithField("stderr", stderr), "Plan result in error")
	case PlanDiff:
		return PlanDiff, errs.WithF(data.WithField("project", projectPath), "Plan result with a diff")
	default:
		return PlanUnknown, errs.WithEF(err, data.WithField("project", projectPath), "Plan result in unknown error")
	}
}

func (c *Client) RunApply(projectPath string) error {
	args := []string{
		"-chdir=" + projectPath,
		"apply",
		"-input=false",
		"-no-color",
	}
	if c.planfile != "" {
		args = append(args, c.planfile)
	}
	logs.WithField("project", projectPath).Info("Running terraform apply")
	stderr, err := c.runner.ExecCmdGetStderr(c.localBinaryPath, args...)
	if err != nil {
		return errs.WithEF(err, data.WithField("stderr", stderr).WithField("path", projectPath), "Apply failed")
	}
	return nil
}

func (c *Client) RunFmt(projectPath string, opts ...string) error {
	logs.WithField("project", projectPath).Info("Running terraform fmt")
	var args []string
	args = append(args, "-chdir="+projectPath, "fmt")
	args = append(args, opts...)
	stderr, err := c.runner.ExecCmdGetStderr(
		c.localBinaryPath,
		args...,
	)

	if err != nil {
		return errs.WithEF(err, data.WithField("stderr", stderr).WithField("path", projectPath), "fmt failed")
	}
	return nil
}
