package runner

import (
	"bytes"
	"github.com/n0rad/go-erlog/logs"
	"io"
	"os"
	"os/exec"
	"strings"
)

type LocalRunner struct {
}

func NewLocalRunner() *LocalRunner {
	return &LocalRunner{}
}

func (r LocalRunner) ExecCmd(head string, args ...string) error {
	return ExecCmd(head, args...)
}

func (r LocalRunner) ExecCmdGetStdout(head string, args ...string) (string, error) {
	return ExecCmdGetOutput(head, args...)
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
