package runner

import (
	"bytes"
	"fmt"
	"github.com/n0rad/go-erlog/errs"
	"golang.org/x/crypto/ssh"
	"golang.org/x/crypto/ssh/agent"
	"io"
	"net"
	"os"
	"os/exec"
	"strings"
)

type SshRunner struct {
	client       *ssh.Client
	sudoPassword string
}

func NewSshRunner(addr string, user string, sudoPassword string) (*SshRunner, error) {
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
		User: user,
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
		client:       client,
		sudoPassword: sudoPassword,
	}, nil
}

func (r SshRunner) ExecCmd(head string, args ...string) error {
	session, err := r.client.NewSession()
	if err != nil {
		return errs.WithE(err, "Failed to create ssh session")
	}
	defer session.Close()

	modes := ssh.TerminalModes{
		ssh.ECHO:          0,     // disable echoing
		ssh.TTY_OP_ISPEED: 14400, // input speed = 14.4kbaud
		ssh.TTY_OP_OSPEED: 14400, // output speed = 14.4kbaud
	}

	err = session.RequestPty("xterm", 80, 40, modes)
	if err != nil {
		return errs.WithE(err, "Failed to request pty")
	}

	var stdout bytes.Buffer
	session.Stdout = &stdout
	in, _ := session.StdinPipe()

	go func(in io.Writer, output *bytes.Buffer) {
		for {
			if strings.Contains(string(output.Bytes()), "[sudo] password for ") {
				_, err = in.Write([]byte(r.sudoPassword + "\n"))
				if err != nil {
					break
				}
				fmt.Println("put the password ---  end .")
				break
			}
		}
	}(in, &stdout)

	if err = session.Run(head + " " + strings.Join(args, " ")); err != nil {
		if exitError, ok := err.(*exec.ExitError); ok {
			fmt.Printf("Command failed with exit code: %d\n", exitError.ExitCode())
		}
		return errs.WithE(err, "Command failed")
	}
	fmt.Print(stdout.String())
	return nil
}

func (r SshRunner) ExecCmdGetStdout(head string, args ...string) (string, error) {
	session, err := r.client.NewSession()
	if err != nil {
		return "", errs.WithE(err, "Failed to create ssh session")
	}
	defer session.Close()

	modes := ssh.TerminalModes{
		ssh.ECHO:          0,     // disable echoing
		ssh.TTY_OP_ISPEED: 14400, // input speed = 14.4kbaud
		ssh.TTY_OP_OSPEED: 14400, // output speed = 14.4kbaud
	}

	err = session.RequestPty("xterm", 80, 40, modes)
	if err != nil {
		return "", errs.WithE(err, "Failed to request pty")
	}

	var stdout bytes.Buffer
	session.Stdout = &stdout
	in, _ := session.StdinPipe()

	go func(in io.Writer, output *bytes.Buffer) {
		for {
			if strings.Contains(string(output.Bytes()), "[sudo] password for ") {
				_, err = in.Write([]byte(r.sudoPassword + "\n"))
				if err != nil {
					break
				}
				fmt.Println("put the password ---  end .")
				break
			}
		}
	}(in, &stdout)

	//err = session.Start()
	//if err != nil {
	//	return "", errs.WithE(err, "Failed to start command")
	//}
	//err = session.Wait()

	if err = session.Run(head + " " + strings.Join(args, " ")); err != nil {
		if exitError, ok := err.(*exec.ExitError); ok {
			fmt.Printf("Command failed with exit code: %d\n", exitError.ExitCode())
		}

		return "", errs.WithE(err, "Command failed")
	}
	return stdout.String(), nil
}

//// Create a session. It is one session per command.
//session, err := client.NewSession()
//if err != nil {
//	return "", err
//}
//defer session.Close()
//var b bytes.Buffer  // import "bytes"
//session.Stdout = &b // get output
//// you can also pass what gets input to the stdin, allowing you to pipe
//// content from client to server
////      session.Stdin = bytes.NewBufferString("My input")
//
//// Finally, run the command
//err = session.Run(cmd)
//return b.String(), err
