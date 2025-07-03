package system

import (
	"github.com/becloudless/becloudless/pkg/system/runner"
)

type System struct {
	SudoRunner *runner.InlineSudoRunner
}

//func (s System) IsSudoWorking() error {
//	_, err := s.Runner.ExecCmdGetStdout("command", "-v", "sudo")
//	if err != nil {
//		return errs.WithE(err, "Sudo is not available")
//	}
//
//	if password == nil || password.Size() == 0 {
//		if stderr, err := s.Runner.ExecCmdGetStderr("sudo", "-n", "true"); err != nil {
//			return errs.WithEF(err, data.WithField("stderr", stderr), "Sudo require a password")
//		}
//	} else {
//		passwordReader := strings.NewReader(password.String() + "\n")
//		if _, err := s.Runner.Exec(passwordReader, os.Stdout, io.Discard, "sudo", "-S", "true"); err != nil {
//			return errs.WithE(err, "Sudo password is probably wrong")
//		}
//	}
//	return nil
//}
