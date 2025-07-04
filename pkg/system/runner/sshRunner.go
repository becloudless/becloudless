package runner

import (
	"bytes"
	"github.com/awnumar/memguard"
	"github.com/n0rad/go-erlog/errs"
	"golang.org/x/crypto/ssh"
	"golang.org/x/crypto/ssh/agent"
	"io"
	"net"
	"os"
	"os/exec"
	"strings"
	"time"
)

type SshRunner struct {
	client       *ssh.Client
	sudoPassword *memguard.LockedBuffer
}

func NewSshRunner(addr string, user string) (*SshRunner, error) {
	// privateKey could be read from a file, or retrieved from another storage
	// source, such as the Secret Service / GNOME Keyring
	//key, err := ssh.ParsePrivateKey([]byte(privateKey))
	//if err != nil {
	//	return "", err
	//}
	// Authentication

	// ssh-agent(1) provides a UNIX socket at $SSH_AUTH_SOCK.
	socket := os.Getenv("SSH_AUTH_SOCK")
	conn, err := net.Dial("unix", socket)
	if err != nil {
		return nil, errs.WithE(err, "Failed to open SSH_AUTH_SOCK")
	}

	agentClient := agent.NewClient(conn)

	config := &ssh.ClientConfig{
		User:    user,
		Timeout: 5 * time.Second,
		// https://github.com/golang/go/issues/19767
		// as clientConfig is non-permissive by default
		// you can set ssh.InsercureIgnoreHostKey to allow any host
		HostKeyCallback: ssh.InsecureIgnoreHostKey(),
		Auth: []ssh.AuthMethod{
			ssh.PublicKeysCallback(agentClient.Signers),
			//ssh.PublicKeys(key),
		},
		//alternatively, you could use a password
		/*
		   Auth: []ssh.AuthMethod{
		       ssh.Password("PASSWORD"),
		   },
		*/
	}

	// Connect
	client, err := ssh.Dial("tcp", net.JoinHostPort(addr, "22"), config)
	if err != nil {
		return nil, errs.WithE(err, "Failed to connect to remote host")
	}

	return &SshRunner{
		client: client,
	}, nil
}

func (r *SshRunner) Exec(stdin io.Reader, stdout io.Writer, stderr io.Writer, head string, args ...string) (int, error) {
	session, err := r.client.NewSession()
	if err != nil {
		return -1, errs.WithE(err, "Failed to create ssh session")
	}
	defer session.Close()

	session.Stdout = stdout
	session.Stderr = stderr
	session.Stdin = stdin

	cmd := head + " " + strings.Join(args, " ")
	if err = session.Run(cmd); err != nil {
		if exitError, ok := err.(*exec.ExitError); ok {
			code := exitError.ExitCode()
			return code, errs.WithE(err, "Command failed")
		}
		return -1, errs.WithE(err, "Command failed")
	}
	return 0, nil
}

func (r *SshRunner) ExecCmd(head string, args ...string) error {
	_, err := r.Exec(os.Stdin, os.Stdout, os.Stderr, head, args...)
	return err
}

func (r *SshRunner) ExecCmdGetStdout(head string, args ...string) (string, error) {
	var stdout bytes.Buffer
	_, err := r.Exec(os.Stdin, &stdout, os.Stderr, head, args...)
	return strings.TrimSpace(stdout.String()), err
}

func (r *SshRunner) ExecCmdGetStderr(head string, args ...string) (string, error) {
	var stderr bytes.Buffer
	_, err := r.Exec(os.Stdin, os.Stdout, &stderr, head, args...)
	return strings.TrimSpace(stderr.String()), err
}
