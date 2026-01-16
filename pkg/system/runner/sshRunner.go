package runner

import (
	"io"
	"net"
	"os"
	"os/exec"
	"strconv"
	"strings"
	"time"

	"github.com/becloudless/becloudless/pkg/utils"
	"github.com/n0rad/go-erlog/data"
	"github.com/n0rad/go-erlog/errs"
	"github.com/n0rad/go-erlog/logs"
	"github.com/n0rad/memguarded"
	"golang.org/x/crypto/ssh"
	"golang.org/x/crypto/ssh/agent"
)

type SshRunner struct {
	genericRunner
	client           *ssh.Client
	connectionConfig *SshConnectionConfig
}

type SshConnectionConfig struct {
	Host            string
	Port            int
	User            string
	Password        *memguarded.Service
	IdentifyFile    string
	InsecureHostKey bool
}

func NewSshRunner(config *SshConnectionConfig) (*SshRunner, error) {
	var auths []ssh.AuthMethod

	if config.IdentifyFile != "" {
		content, err := os.ReadFile(config.IdentifyFile)
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

	if config.Password.IsSet() {
		auths = append(auths, ssh.PasswordCallback(func() (string, error) {
			buff, err := config.Password.Get()
			if err != nil {
				return "", errs.WithE(err, "Failed to open ssh password enclave")
			}
			defer buff.Destroy()
			return buff.String(), nil
		}))
	}

	hostKeyCallback := ssh.InsecureIgnoreHostKey()
	if !config.InsecureHostKey {
		hostKeyCallback = ssh.FixedHostKey(nil) // TODO: implement proper host key checking
	}

	clientConfig := &ssh.ClientConfig{
		User:            config.User,
		Timeout:         5 * time.Second,
		HostKeyCallback: hostKeyCallback,
		Auth:            auths,
	}

	port := config.Port
	if port == 0 {
		port = 22
	}

	// Connect
	client, err := ssh.Dial("tcp", net.JoinHostPort(config.Host, strconv.Itoa(config.Port)), clientConfig)
	if err != nil {
		return nil, errs.WithE(err, "Failed to connect to remote host")
	}

	s := &SshRunner{
		client:           client,
		connectionConfig: config,
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

	cmd := head + " " + strings.Join(utils.ShellQuoteArgs(args), " ")
	if logs.IsTraceEnabled() {
		logs.WithField("command", cmd).WithField("host", r.connectionConfig.Host).Trace("Running ssh external command")
	}
	if err = session.Run(cmd); err != nil {
		if exitError, ok := err.(*exec.ExitError); ok {
			code := exitError.ExitCode()
			return code, errs.WithE(err, "Command failed")
		}
		return -1, errs.WithE(err, "Command failed")
	}
	return 0, nil
}
