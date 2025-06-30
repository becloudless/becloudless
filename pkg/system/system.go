package system

import (
	"github.com/becloudless/becloudless/pkg/system/runner"
	"github.com/n0rad/go-erlog/errs"
)

type System struct {
	Runner runner.Runner
}

func (s System) IsSudoAvailableAndPasswordRequired() (bool, bool, error) {
	err := s.Runner.ExecCmd("command", "-v", "sudo")
	if err != nil {
		return false, false, nil
	}

	stdout, err := s.Runner.ExecCmdGetStdout("sudo", "-n", "true")
	if err != nil {
		return true, false, errs.WithE(err, "Failed to get sudo")
	}
	if stdout == "sudo: a password is required" {
		return true, true, nil
	}
	return true, false, nil
}
