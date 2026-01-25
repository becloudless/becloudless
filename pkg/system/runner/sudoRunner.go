package runner

import (
	"io"

	"github.com/n0rad/go-erlog/data"
	"github.com/n0rad/go-erlog/errs"
	"github.com/n0rad/memguarded"
)

type SudoRunner struct {
	genericRunner
	parent   Runner
	password *memguarded.Service
	inline   bool
}

// the sudo commands are inlined in the command to run, do not wrap the command again with sudo
func (s *SudoRunner) WithInline(inline bool) *SudoRunner {
	s.inline = inline
	return s
}

func IsSudoRunnableWithoutPassword(local Runner) error {
	if stderr, err := local.ExecCmdGetStderr("sudo", "-n", "true"); err != nil {
		return errs.WithEF(err, data.WithField("stderr", stderr), "Sudo require a password")
	}
	return nil
}

func NewSudoRunner(parent Runner, password *memguarded.Service) (*SudoRunner, error) {
	run := &SudoRunner{
		parent:   parent,
		password: password,
	}
	run.Runner = run

	_, err := NewShellRunner(parent).ExecCmdGetStdout("command", "-v", "sudo")
	if err != nil {
		return nil, errs.WithE(err, "Sudo is not available")
	}

	if password == nil || !password.IsSet() {
		if err := IsSudoRunnableWithoutPassword(parent); err != nil {
			return nil, err
		}
	} else {
		if _, err := run.ExecCmdGetStderr("true"); err != nil {
			return nil, errs.WithE(err, "Sudo password is probably wrong")
		}
	}
	return run, nil
}

func (r SudoRunner) Exec(envs *[]string, stdin io.Reader, stdout io.Writer, stderr io.Writer, head string, args ...string) (int, error) {
	// TODO stdin is not used since replaced by the sudo password. How to notify the caller?

	//var passwordReader io.Reader
	//openedPassword, err := r.password.Open()
	//if err != nil {
	//	return -1, errs.WithE(err, "Failed to open sudo password enclave")
	//}
	//defer openedPassword.Destroy()
	//
	//if openedPassword != nil && openedPassword.Size() > 0 {
	//	passwordReader = strings.NewReader(openedPassword.String() + "\n")
	//} else {
	//	passwordReader = strings.NewReader("\n")
	//}

	newHead := head
	newArgs := args

	if !r.inline {
		newHead = "sudo"
		//-p ""
		newArgs = append([]string{"-S", head}, args...)
	}

	return r.parent.Exec(envs, r.password.Reader(), stdout, stderr, newHead, newArgs...)
}
