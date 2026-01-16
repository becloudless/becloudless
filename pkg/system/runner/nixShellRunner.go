package runner

import (
	"io"
	"strings"

	"github.com/becloudless/becloudless/pkg/utils"
)

type NixShellRunner struct {
	genericRunner
	parent   Runner
	Packages []string
}

func NewNixShellRunner(parent Runner, packages ...string) *NixShellRunner {
	n := &NixShellRunner{
		parent:   parent,
		Packages: packages,
	}
	n.Runner = n
	return n
}

func (r NixShellRunner) Exec(envs *[]string, stdin io.Reader, stdout io.Writer, stderr io.Writer, head string, args ...string) (int, error) {
	newArgs := []string{"--extra-experimental-features", "nix-command flakes"} // assume we want that
	for _, pkg := range r.Packages {
		newArgs = append(newArgs, "-p", pkg)
	}

	newArgs = append(newArgs, "--run", head+" "+strings.Join(utils.ShellQuoteArgs(args), " "))
	return r.parent.Exec(envs, stdin, stdout, stderr, "nix-shell", newArgs...)
}
