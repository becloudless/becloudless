package runner

import "io"

type Runner interface {
	Exec(stdin io.Reader, head string, args ...string) (stdout string, stderr string, exitCode int, err error)
}
