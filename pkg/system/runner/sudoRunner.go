package runner

import (
	"bytes"
	"github.com/awnumar/memguard"
	"github.com/n0rad/go-erlog/data"
	"github.com/n0rad/go-erlog/errs"
	"io"
	"os"
	"strings"
)

type SudoRunner struct {
	ParentRunner Runner
	password     *memguard.LockedBuffer
}

func NewSudoRunner(parent Runner, password *memguard.LockedBuffer) (*SudoRunner, error) {
	run := SudoRunner{
		ParentRunner: parent,
		password:     password,
	}
	_, err := parent.ExecCmdGetStdout("command", "-v", "sudo")
	if err != nil {
		return nil, errs.WithE(err, "Sudo is not available")
	}

	if password == nil || password.Size() == 0 {
		if stderr, err := parent.ExecCmdGetStderr("sudo", "-n", "true"); err != nil {
			return nil, errs.WithEF(err, data.WithField("stderr", stderr), "Sudo require a password")
		}
	} else {
		if _, err := run.ExecCmdGetStderr("true"); err != nil {
			return nil, errs.WithE(err, "Sudo password is probably wrong")
		}
	}
	return &run, nil
}

func (r SudoRunner) Exec(stdin io.Reader, stdout io.Writer, stderr io.Writer, head string, args ...string) (int, error) {
	// TODO stdin is not used since replaced by the sudo password
	passwordReader := strings.NewReader(r.password.String() + "\n")
	//-p ""
	i := append([]string{"-S", head}, args...)
	return r.ParentRunner.Exec(passwordReader, stdout, stderr, "sudo", i...)
}

func (r SudoRunner) ExecCmd(head string, args ...string) error {
	_, err := r.Exec(os.Stdin, os.Stdout, os.Stderr, head, args...)
	return err
}

func (r SudoRunner) ExecCmdGetStdout(head string, args ...string) (string, error) {
	var stdout bytes.Buffer
	_, err := r.Exec(os.Stdin, &stdout, os.Stderr, head, args...)
	return stdout.String(), err
}

func (r SudoRunner) ExecCmdGetStderr(head string, args ...string) (string, error) {
	var stderr bytes.Buffer
	_, err := r.Exec(os.Stdin, os.Stdout, &stderr, head, args...)
	return stderr.String(), err
}
