package nixos

import (
	"io"
	"os"
	"regexp"
	"sync"

	"github.com/becloudless/becloudless/pkg/system/runner"
	"github.com/n0rad/go-erlog/errs"
	"github.com/n0rad/go-erlog/logs"
)

// corruptedStorePattern matches the errors of nix on a path of the store that is empty or truncated (ex: after a crash of the
// machine, the path is registered as valid but its content was never written):
//   - `error parsing derivation '/nix/store/...drv': file is empty (possible filesystem corruption)`
//   - `syntax error, unexpected end of file` at line 1 column 1 of a file of the store (ex: the flake.nix of a flake input)
var corruptedStorePattern = regexp.MustCompile(`possible filesystem corruption|(?s)syntax error, unexpected end of file.{0,300}:1:1`)

// storeRepairs are tried in order, each one followed by a new run of the command, as long as it fails with a corrupted store.
var storeRepairs = []struct {
	name   string
	repair func(run runner.Runner) error
}{
	{"garbage collection", collectStoreGarbage},
	{"store verification", verifyStore},
}

// nixStoreCmd runs nix-store through the nix daemon, see execNixosRebuild.
func nixStoreCmd(run runner.Runner, args ...string) error {
	return run.ExecCmd("env", append([]string{"NIX_REMOTE=daemon", "nix-store"}, args...)...)
}

// collectStoreGarbage removes the paths nothing uses, which is what removes a corrupted path that is not referenced anymore, and the
// derivations: they are only kept for the outputs they are the source of (`keep-derivations`), are always created again by the next
// evaluation, and a truncated one is the usual victim. A truncated derivation that is still referenced after that is deleted explicitly,
// an empty one is never valid.
func collectStoreGarbage(run runner.Runner) error {
	if err := nixStoreCmd(run, "--gc", "--option", "keep-derivations", "false"); err != nil {
		return errs.WithE(err, "Failed to collect the garbage of the nix store")
	}
	if err := run.ExecCmd("env", "NIX_REMOTE=daemon", "sh", "-c",
		`find /nix/store -maxdepth 1 -type f -size 0 -name '*.drv' | xargs -r nix-store --delete --ignore-liveness`); err != nil {
		return errs.WithE(err, "Failed to delete the empty derivations of the nix store")
	}
	return nil
}

// verifyStore checks the content of every path of the store and fetches again the ones that are modified (slow, it hashes the whole store).
func verifyStore(run runner.Runner) error {
	if err := nixStoreCmd(run, "--verify", "--check-contents", "--repair"); err != nil {
		return errs.WithE(err, "Failed to verify and repair the nix store")
	}
	return nil
}

// execCapturingStderr runs the command, with its stderr still sent to ours, and returns the end of it.
func execCapturingStderr(run runner.Runner, head string, args ...string) (string, error) {
	tail := &tailBuffer{max: 64 * 1024}
	_, err := run.Exec(nil, os.Stdin, os.Stdout, io.MultiWriter(os.Stderr, tail), head, args...)
	return tail.String(), err
}

// execWithStoreRepair runs the command and, when it fails because of a corrupted nix store, repairs the store and runs it again.
func execWithStoreRepair(run runner.Runner, head string, args ...string) error {
	stderr, err := execCapturingStderr(run, head, args...)
	for _, step := range storeRepairs {
		if err == nil || !corruptedStorePattern.MatchString(stderr) {
			return err
		}
		logs.WithE(err).WithField("repair", step.name).Warn("The nix store is corrupted, repairing it before trying again")
		if repairErr := step.repair(run); repairErr != nil {
			// the command is run again anyway: the repair may have removed the corrupted path before failing
			logs.WithE(repairErr).WithField("repair", step.name).Warn("Failed to repair the nix store")
		}
		stderr, err = execCapturingStderr(run, head, args...)
	}
	return err
}

// tailBuffer keeps the last max bytes written to it.
type tailBuffer struct {
	mu   sync.Mutex
	max  int
	data []byte
}

func (b *tailBuffer) Write(p []byte) (int, error) {
	b.mu.Lock()
	defer b.mu.Unlock()
	b.data = append(b.data, p...)
	if len(b.data) > b.max {
		b.data = append([]byte(nil), b.data[len(b.data)-b.max:]...)
	}
	return len(p), nil
}

func (b *tailBuffer) String() string {
	b.mu.Lock()
	defer b.mu.Unlock()
	return string(b.data)
}
