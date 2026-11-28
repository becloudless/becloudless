package utils

import (
	"bufio"
	"bytes"
	"fmt"
	"os"
	"strconv"
	"strings"
	"syscall"

	"github.com/n0rad/go-erlog/errs"
	"golang.org/x/term"
)

// AskConfirm requires the exact answer "yes", anything else is a refusal
func AskConfirm(question string) (bool, error) {
	if !term.IsTerminal(int(os.Stdin.Fd())) {
		return false, errs.With("Confirmation is required but stdin is not a terminal")
	}
	fmt.Print(question + " (type yes to continue): ")
	answer, err := bufio.NewReader(os.Stdin).ReadString('\n')
	if err != nil {
		return false, errs.WithE(err, "Failed to read confirmation")
	}
	return strings.TrimSpace(answer) == "yes", nil
}

// AskChoice returns the selected item of choices
func AskChoice(question string, choices []string) (string, error) {
	if !term.IsTerminal(int(os.Stdin.Fd())) {
		return "", errs.With("A choice is required but stdin is not a terminal")
	}
	reader := bufio.NewReader(os.Stdin)
	for {
		fmt.Println(question)
		for i, choice := range choices {
			fmt.Printf("  %d) %s\n", i+1, choice)
		}
		fmt.Print("Number: ")
		answer, err := reader.ReadString('\n')
		if err != nil {
			return "", errs.WithE(err, "Failed to read choice")
		}
		index, err := strconv.Atoi(strings.TrimSpace(answer))
		if err == nil && index >= 1 && index <= len(choices) {
			return choices[index-1], nil
		}
		fmt.Println("Invalid choice. Try again")
	}
}

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
