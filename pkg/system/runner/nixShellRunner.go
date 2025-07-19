package runner

import (
	"io"
)

type NixShellRunner struct {
	genericRunner
	Packages []string
}

func NewNixShellRunner(parent Runner, packages ...string) *NixShellRunner {
	return &NixShellRunner{
		genericRunner: genericRunner{
			parent: parent,
		},
		Packages: packages,
	}
}

func (r NixShellRunner) Exec(envs *[]string, stdin io.Reader, stdout io.Writer, stderr io.Writer, head string, args ...string) (int, error) {
	newArgs := []string{"--extra-experimental-features", "nix-command flakes"} // assume we want that
	for _, pkg := range r.Packages {
		newArgs = append(newArgs, "-p", pkg)
	}
	newArgs = append(newArgs, "--run", head)
	newArgs = append(newArgs, args...)
	return r.parent.Exec(envs, stdin, stdout, stderr, "nix-shell", newArgs...)
}
