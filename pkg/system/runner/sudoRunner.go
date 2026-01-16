package runner

import (
	"io"
	"strings"

	"github.com/n0rad/go-erlog/data"
	"github.com/n0rad/go-erlog/errs"
)

type SudoRunner struct {
	genericRunner
	parent   Runner
	password []byte
}

func NewSudoRunner(parent Runner, password []byte) (*SudoRunner, error) {
	run := &SudoRunner{
		parent:   parent,
		password: password,
	}
	run.Runner = run

	_, err := NewShellRunner(parent).ExecCmdGetStdout("command", "-v", "sudo")
	if err != nil {
		return nil, errs.WithE(err, "Sudo is not available")
	}

	if password == nil || len(password) == 0 {
		if stderr, err := parent.ExecCmdGetStderr("sudo", "-n", "true"); err != nil {
			return nil, errs.WithEF(err, data.WithField("stderr", stderr), "Sudo require a password")
		}
	} else {
		if _, err := run.ExecCmdGetStderr("true"); err != nil {
			return nil, errs.WithE(err, "Sudo password is probably wrong")
		}
	}
	return run, nil
}

func (r SudoRunner) Exec(envs *[]string, stdin io.Reader, stdout io.Writer, stderr io.Writer, head string, args ...string) (int, error) {
	// TODO stdin is not used since replaced by the sudo password
	passwordReader := strings.NewReader(string(r.password) + "\n")
	//-p ""
	i := append([]string{"-S", head}, args...)
	return r.parent.Exec(envs, passwordReader, stdout, stderr, "sudo", i...)
}
