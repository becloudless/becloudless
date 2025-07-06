package runner

import (
	"bytes"
	"github.com/awnumar/memguard"
	"github.com/n0rad/go-erlog/errs"
	"github.com/n0rad/go-erlog/logs"
	"io"
	"os"
	"os/exec"
	"strings"
)

type LocalRunner struct {
	sudoPassword *memguard.LockedBuffer
}

func NewLocalRunner() *LocalRunner {
	return &LocalRunner{}
}

func (r *LocalRunner) Exec(envs *[]string, stdin io.Reader, stdout io.Writer, stderr io.Writer, head string, args ...string) (int, error) {
	cmd := exec.Command(head, args...)
	if envs != nil {
		cmd.Env = append(cmd.Environ(), *envs...)
	}
	cmd.Stderr = stderr
	cmd.Stdout = stdout
	cmd.Stdin = stdin
	if stderr == nil {
		cmd.Stderr = os.Stderr
	}
	if stdout == nil {
		cmd.Stdout = os.Stdout
	}
	if stdin == nil {
		cmd.Stdin = os.Stdin
	}
	if logs.IsTraceEnabled() {
		logs.WithField("command", strings.Join([]string{head, " ", strings.Join(args, " ")}, " ")).Debug("Running external command")
	}
	if err := cmd.Start(); err != nil {
		return -1, errs.WithE(err, "Failed to start command")
	}
	err := cmd.Wait()
	return cmd.ProcessState.ExitCode(), err
}

func (r *LocalRunner) ExecCmd(head string, args ...string) error {
	_, err := r.Exec(nil, os.Stdin, os.Stdout, os.Stderr, head, args...)
	return err
}

func (r *LocalRunner) ExecCmdGetStdout(head string, args ...string) (string, error) {
	var stdout bytes.Buffer
	_, err := r.Exec(nil, os.Stdin, &stdout, os.Stderr, head, args...)
	return stdout.String(), err
}

func (r *LocalRunner) ExecCmdGetStderr(head string, args ...string) (string, error) {
	var stderr bytes.Buffer
	_, err := r.Exec(nil, os.Stdin, &stderr, os.Stderr, head, args...)
	return stderr.String(), err
}

// ////////////////////////////////

func ExecCmdGetStdoutStderrExitCode(head string, parts ...string) (string, string, int, error) {
	var stdout bytes.Buffer
	var stderr bytes.Buffer

	if logs.IsDebugEnabled() {
		logs.WithField("command", strings.Join([]string{head, " ", strings.Join(parts, " ")}, " ")).Debug("Running external command")
	}
	cmd := exec.Command(head, parts...)
	cmd.Stderr = &stderr
	cmd.Stdout = &stdout
	cmd.Start()
	err := cmd.Wait()
	return strings.TrimSpace(stdout.String()), strings.TrimSpace(stderr.String()), cmd.ProcessState.ExitCode(), err
}

func ExecCmdGetStderrExitCode(head string, parts ...string) (string, int, error) {
	var stderr bytes.Buffer

	if logs.IsDebugEnabled() {
		logs.WithField("command", strings.Join([]string{head, " ", strings.Join(parts, " ")}, " ")).Debug("Running external command")
	}
	cmd := exec.Command(head, parts...)
	cmd.Stderr = &stderr
	cmd.Stdout = os.Stdout
	cmd.Start()
	err := cmd.Wait()
	return strings.TrimSpace(stderr.String()), cmd.ProcessState.ExitCode(), err
}

func ExecCmdGetStdoutAndStderr(head string, parts ...string) (string, string, error) {
	var stdout bytes.Buffer
	var stderr bytes.Buffer

	if logs.IsDebugEnabled() {
		logs.WithField("command", strings.Join([]string{head, " ", strings.Join(parts, " ")}, " ")).Debug("Running external command")
	}
	cmd := exec.Command(head, parts...)
	cmd.Stdout = &stdout
	cmd.Stderr = &stderr
	cmd.Start()
	err := cmd.Wait()
	return strings.TrimSpace(stdout.String()), strings.TrimSpace(stderr.String()), err
}

func ExecCmdGetOutput(head string, parts ...string) (string, error) {
	var stdout bytes.Buffer

	if logs.IsDebugEnabled() {
		logs.WithField("command", strings.Join([]string{head, " ", strings.Join(parts, " ")}, " ")).Debug("Running external command")
	}
	cmd := exec.Command(head, parts...)
	cmd.Stdout = &stdout
	cmd.Stderr = os.Stderr
	cmd.Start()
	err := cmd.Wait()
	return strings.TrimSpace(stdout.String()), err
}

func ExecCmdGetStderr(head string, parts ...string) (string, error) {
	var stderr bytes.Buffer

	if logs.IsDebugEnabled() {
		logs.WithField("command", strings.Join([]string{head, " ", strings.Join(parts, " ")}, " ")).Debug("Running external command")
	}
	cmd := exec.Command(head, parts...)
	cmd.Stdout = os.Stdout
	cmd.Stderr = &stderr
	cmd.Start()
	err := cmd.Wait()
	return strings.TrimSpace(stderr.String()), err
}

func ExecCmdRedirectOutputs(stdout, stderr io.Writer, head string, parts ...string) error {

	if logs.IsDebugEnabled() {
		logs.WithField("command", strings.Join([]string{head, " ", strings.Join(parts, " ")}, " ")).Debug("Running external command")
	}
	cmd := exec.Command(head, parts...)
	cmd.Stdout = stdout
	cmd.Stderr = stderr
	cmd.Start()
	err := cmd.Wait()
	return err
}

// ExecCmd will execute the given command (head) with its arguments (parts) and
// use default Stdout/Stdin and Stderr
func ExecCmd(head string, parts ...string) error {
	if logs.IsDebugEnabled() {
		logs.WithField("command", strings.Join([]string{head, " ", strings.Join(parts, " ")}, " ")).Debug("Running external command")
	}
	cmd := exec.Command(head, parts...)
	cmd.Stdout = os.Stdout
	cmd.Stdin = os.Stdin
	cmd.Stderr = os.Stderr
	return cmd.Run()
}

// ExecCmdNoOutput will execute the given command (head) with its arguments (parts) and
// redirect the output (both stderr & stdout) to io.Discard.
func ExecCmdNoOutput(head string, parts ...string) error {
	if logs.IsDebugEnabled() {
		logs.WithField("command", strings.Join([]string{head, " ", strings.Join(parts, " ")}, " ")).Debug("Running external command")
	}

	cmd := exec.Command(head, parts...)

	cmd.Stdout = io.Discard
	cmd.Stderr = io.Discard

	return cmd.Run()
}
