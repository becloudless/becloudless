package runner

type Runner interface {
	ExecCmdGetStdout(head string, args ...string) (string, error)
	ExecCmd(head string, args ...string) error
}
