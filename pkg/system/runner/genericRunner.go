package runner

import (
	"bytes"
	"io"
	"os"
	"strings"
)

type genericRunner struct {
	parent Runner
}

func (r genericRunner) Exec(envs *[]string, stdin io.Reader, stdout io.Writer, stderr io.Writer, head string, args ...string) (int, error) {
	return r.parent.Exec(envs, stdin, stdout, stderr, head, args...)
}

func (r genericRunner) ExecCmd(head string, args ...string) error {
	_, err := r.Exec(nil, os.Stdin, os.Stdout, os.Stderr, head, args...)
	return err
}

func (r genericRunner) ExecCmdGetStdout(head string, args ...string) (string, error) {
	var stdout bytes.Buffer
	_, err := r.Exec(nil, os.Stdin, &stdout, os.Stderr, head, args...)
	return strings.TrimSpace(stdout.String()), err
}

func (r genericRunner) ExecCmdGetStderr(head string, args ...string) (string, error) {
	var stderr bytes.Buffer
	_, err := r.Exec(nil, os.Stdin, os.Stdout, &stderr, head, args...)
	return strings.TrimSpace(stderr.String()), err
}
