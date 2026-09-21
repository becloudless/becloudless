// Command build regenerates this chart's derived artifacts
// (schema/resources/*.json, schema/values.schema.json and
// templates/_generated.tpl) from CRDs.yaml. Run it from the chart's root
// directory:
//
//	go run ./build
package main

import (
	"fmt"
	"os"
)

func main() {
	if err := run(); err != nil {
		fmt.Fprintln(os.Stderr, "error:", err)
		os.Exit(1)
	}
}
