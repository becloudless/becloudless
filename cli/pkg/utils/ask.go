package utils

import (
	"bytes"
	"fmt"
	"syscall"

	"github.com/n0rad/go-erlog/errs"
	"golang.org/x/term"
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

		if len(pass) > 0 && bytes.Equal(pass, pass2) {
			return pass, nil
		}
		fmt.Println(confirmationMatchErrorMessage + ". Try again")
	}
}
