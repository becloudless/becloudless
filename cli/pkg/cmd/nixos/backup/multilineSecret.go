package backup

import (
	"bufio"
	"fmt"
	"os"

	"github.com/n0rad/go-erlog/errs"
	"golang.org/x/term"
)

// readMultilineSecret reads a multiline secret (e.g. a PEM/OpenSSH private
// key) from the terminal without echoing it back. Unlike
// memguarded.Service.AskSecret/FromStdin (which stop at the first newline,
// fine for single-line passwords but not for multiline key material), this
// puts the terminal in raw mode and keeps reading until either an empty
// line or EOF (Ctrl-D) is received.
func readMultilineSecret(prompt string) ([]byte, error) {
	fd := int(os.Stdin.Fd())
	if !term.IsTerminal(fd) {
		return nil, errs.With("Cannot ask secret, not in a terminal")
	}

	fmt.Println(prompt + " (end with an empty line or Ctrl-D):")
	oldState, err := term.MakeRaw(fd)
	if err != nil {
		return nil, errs.WithE(err, "Failed to set terminal to raw mode")
	}
	defer term.Restore(fd, oldState)

	reader := bufio.NewReader(os.Stdin)
	var secret []byte
	var lastWasNewline bool
	for {
		b, err := reader.ReadByte()
		if err != nil {
			break // EOF (Ctrl-D)
		}
		if b == '\r' {
			b = '\n'
		}
		if b == '\n' {
			// Echo a real newline since raw mode doesn't do it for us.
			fmt.Print("\r\n")
			if lastWasNewline {
				break // empty line -> end of input
			}
			lastWasNewline = true
		} else {
			lastWasNewline = false
		}
		secret = append(secret, b)
	}
	fmt.Print("\r\n")

	return secret, nil
}
