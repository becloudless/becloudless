package runner

import (
	"bytes"
	"os"
	"strings"
)

type genericRunner struct {
	Runner
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
