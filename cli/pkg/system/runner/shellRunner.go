package runner

import (
	"io"
	"strings"
)

type Shell string

const (
	sh   Shell = "sh"
	bash Shell = "bash"
)

type ShellRunner struct {
	genericRunner
	parent Runner
	shell  Shell
	strict bool
}

func NewShellRunner(parent Runner) *ShellRunner {
	n := &ShellRunner{
		parent: parent,
		shell:  bash,
		strict: true,
	}
	n.Runner = n
	return n
}

func (r *ShellRunner) SetStrict(strict bool) *ShellRunner {
	r.strict = strict
	return r
}

func (r *ShellRunner) Exec(envs *[]string, stdin io.Reader, stdout io.Writer, stderr io.Writer, head string, args ...string) (int, error) {
	newArgs := []string{string(r.shell)}
	if r.strict {
		newArgs = append(newArgs, "-euo", "pipefail")
	}
	newArgs = append(newArgs, "-c", strings.Trim(head+" "+strings.Join(args, " "), " "))
	return r.parent.Exec(envs, stdin, stdout, stderr, "/usr/bin/env", newArgs...)
}
