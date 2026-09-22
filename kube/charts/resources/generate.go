// Command build regenerates this chart's derived artifacts
// (schema/resources/*.json, schema/values.schema.json and
// templates/_generated.tpl) from resources.yaml. Run it from the chart's root
// directory:
//
//	go run .
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
