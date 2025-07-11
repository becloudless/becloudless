package runner

import (
	"bytes"
	"github.com/n0rad/go-erlog/data"
	"github.com/n0rad/go-erlog/errs"
	"io"
	"os"
	"strings"
)

type InlineSudoRunner struct {
	ParentRunner Runner
	password     []byte
}

func NewInlineSudoRunner(parent Runner, password []byte) (*InlineSudoRunner, error) {
	run := InlineSudoRunner{
		ParentRunner: parent,
		password:     password,
	}
	_, err := parent.ExecCmdGetStdout("command", "-v", "sudo")
	if err != nil {
		return nil, errs.WithE(err, "Sudo is not available")
	}

	if password == nil || len(password) == 0 {
		if stderr, err := parent.ExecCmdGetStderr("sudo", "-n", "true"); err != nil {
			return nil, errs.WithEF(err, data.WithField("stderr", stderr), "Sudo require a password")
		}
	} else {
		if _, err := run.ExecCmdGetStderr("sudo", "-S", "true"); err != nil {
			return nil, errs.WithE(err, "Sudo password is probably wrong")
		}
	}
	return &run, nil
}

func (r InlineSudoRunner) Exec(stdin io.Reader, stdout io.Writer, stderr io.Writer, head string, args ...string) (int, error) {
	// TODO stdin is not used since replaced by the sudo password
	var passwordReader io.Reader
	if r.password != nil && len(r.password) > 0 {
		passwordReader = strings.NewReader(string(r.password) + "\n")
	} else {
		passwordReader = strings.NewReader("\n")
	}
	return r.ParentRunner.Exec(nil, passwordReader, stdout, stderr, head, args...)
}

func (r InlineSudoRunner) ExecCmd(head string, args ...string) error {
	_, err := r.Exec(os.Stdin, os.Stdout, os.Stderr, head, args...)
	return err
}

func (r InlineSudoRunner) ExecCmdGetStdout(head string, args ...string) (string, error) {
	var stdout bytes.Buffer
	_, err := r.Exec(os.Stdin, &stdout, os.Stderr, head, args...)
	return stdout.String(), err
}

func (r InlineSudoRunner) ExecCmdGetStderr(head string, args ...string) (string, error) {
	var stderr bytes.Buffer
	_, err := r.Exec(os.Stdin, os.Stdout, &stderr, head, args...)
	return stderr.String(), err
}
