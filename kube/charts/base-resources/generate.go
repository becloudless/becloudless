package main

import (
	"fmt"
	"os"

	"resourceschart/generate"
)

func main() {
	if err := generate.Run(); err != nil {
		fmt.Fprintln(os.Stderr, "error:", err)
		os.Exit(1)
	}
}
