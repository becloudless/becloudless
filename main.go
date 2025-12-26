package main

import (
	"embed"
	"os"

	"github.com/becloudless/becloudless/pkg/bcl"
	"github.com/becloudless/becloudless/pkg/cmd"
	"github.com/n0rad/go-erlog/logs"
	_ "github.com/n0rad/go-erlog/register"
)

//go:embed all:assets kube
var Embedded embed.FS
var Version = "0.0.0"

//go:generate ./dist-tools/go-jsonschema -p schema --schema-root-type global=Global ./nixos/modules/nixos/global/default.schema.json -o dist/schema/something.go
func main() {
	bcl.BCL.Embedded = &Embedded
	bcl.BCL.Version = Version

	if err := cmd.RootCmd().Execute(); err != nil {
		logs.WithE(err).Fatal("Command failed")
	}
	os.Exit(0)
}
