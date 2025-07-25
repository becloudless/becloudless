package utils

import (
	"bytes"
	"fmt"
	"github.com/n0rad/go-erlog/errs"
	"golang.org/x/term"
	"syscall"
)

// AskPassword
// empty confirmationMatchError means no confirmation
func AskPassword(question string, confirmationMatchErrorMessage string) ([]byte, error) {
	for {
		fmt.Print(question + " ")
		pass, err := term.ReadPassword(syscall.Stdin)
		if err != nil {
			return []byte{}, errs.WithE(err, "Failed to read password")
		}
		fmt.Println()

		if confirmationMatchErrorMessage == "" {
			return pass, nil
		}

		fmt.Print("Confirm? ")
		pass2, err := term.ReadPassword(syscall.Stdin)
		if err != nil {
			return []byte{}, errs.WithE(err, "Failed to read password")
		}
		fmt.Println()

		if bytes.Equal(pass, pass2) {
			return pass, nil
		}
		fmt.Println(confirmationMatchErrorMessage + ". Try again")
	}
}
