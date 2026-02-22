package runner

import "io"

type Runner interface {
	Exec(envs *[]string, stdin io.Reader, stdout io.Writer, stderr io.Writer, head string, args ...string) (int, error)
	ExecCmd(head string, args ...string) error
	ExecCmdGetStdout(head string, args ...string) (string, error)
	ExecCmdGetStderr(head string, args ...string) (string, error)
}
