package system

import (
	"github.com/awnumar/memguard"
	"github.com/becloudless/becloudless/pkg/system/runner"
	"github.com/n0rad/go-erlog/data"
	"github.com/n0rad/go-erlog/errs"
)

type System struct {
	Runner runner.Runner
}

func (s System) IsSudoWorking(password *memguard.LockedBuffer) error {
	err := s.Runner.ExecCmd("command", "-v", "sudo")
	if err != nil {
		return errs.WithE(err, "Sudo is not available")
	}

	if password == nil || password.Size() == 0 {
		if stderr, err := s.Runner.ExecCmdGetStderr("sudo", "-n", "true"); err != nil {
			return errs.WithEF(err, data.WithField("stderr", stderr), "Sudo require a password")
		}
	} else {
		s.Runner.SupportSudoPassword(password)
		if stderr, err := s.Runner.ExecCmdGetStderr("sudo", "true"); err != nil {
			return errs.WithEF(err, data.WithField("stderr", stderr), "Sudo password is not working")
		}
	}
	return nil
}
