package main

import (
	"fmt"
	"os"

	"github.com/becloudless/becloudless/kube/charts/base/build"
)

func main() {
	if err := build.Build(); err != nil {
		fmt.Fprintln(os.Stderr, "error:", err)
		os.Exit(1)
	}
}
