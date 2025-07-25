package runner

import (
	"github.com/awnumar/memguard"
	"github.com/n0rad/go-erlog/data"
	"github.com/n0rad/go-erlog/errs"
	"golang.org/x/crypto/ssh"
	"golang.org/x/crypto/ssh/agent"
	"io"
	"net"
	"os"
	"os/exec"
	"strconv"
	"strings"
	"time"
)

type SshRunner struct {
	genericRunner
	client       *ssh.Client
	sudoPassword *memguard.LockedBuffer
}

func NewSshRunner(addr string, port int, user string, password []byte, identifyFile string) (*SshRunner, error) {
	var auths []ssh.AuthMethod

	if identifyFile != "" {
		content, err := os.ReadFile(identifyFile)
		if err != nil {
			return nil, errs.WithE(err, "Failed to read identify file")
		}
		key, err := ssh.ParsePrivateKey(content)
		if err != nil {
			return nil, errs.WithE(err, "Failed to read identify file")
		}
		auths = append(auths, ssh.PublicKeys(key))
	}

	if socket := os.Getenv("SSH_AUTH_SOCK"); socket != "" {
		conn, err := net.Dial("unix", socket)
		if err != nil {
			return nil, errs.WithE(err, "Failed to open SSH_AUTH_SOCK")
		}
		agentClient := agent.NewClient(conn)
		auths = append(auths, ssh.PublicKeysCallback(agentClient.Signers))
	}

	if len(password) > 0 {
		auths = append(auths, ssh.PasswordCallback(func() (secret string, err error) {
			if password == nil {
				return "", err
			}
			return string(password), nil
		}))
	}

	config := &ssh.ClientConfig{
		User:            user,
		Timeout:         5 * time.Second,
		HostKeyCallback: ssh.InsecureIgnoreHostKey(), // TODO should not always be insecure
		Auth:            auths,
	}

	// Connect
	client, err := ssh.Dial("tcp", net.JoinHostPort(addr, strconv.Itoa(port)), config)
	if err != nil {
		return nil, errs.WithE(err, "Failed to connect to remote host")
	}

	s := &SshRunner{
		client: client,
	}
	s.Runner = s
	return s, nil
}

func (r *SshRunner) Exec(envs *[]string, stdin io.Reader, stdout io.Writer, stderr io.Writer, head string, args ...string) (int, error) {
	session, err := r.client.NewSession()
	if err != nil {
		return -1, errs.WithE(err, "Failed to create ssh session")
	}
	defer session.Close()

	if envs != nil {
		for _, e := range *envs {
			n := strings.SplitN(e, "=", 2)
			v := ""
			if len(n) == 2 {
				v = n[1]
			}
			if err := session.Setenv(n[0], v); err != nil {
				return -1, errs.WithEF(err, data.WithField("env", n[0]), "Failed to set env to ssh runner session")
			}
		}
	}
	session.Stdout = stdout
	session.Stderr = stderr
	session.Stdin = stdin
	if stderr == nil {
		session.Stderr = os.Stderr
	}
	if stdout == nil {
		session.Stdout = os.Stdout
	}
	if stdin == nil {
		session.Stdin = os.Stdin
	}

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
