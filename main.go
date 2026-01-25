package main

import (
	"embed"
	"os"
	"os/signal"

	"github.com/awnumar/memguard"
	"github.com/becloudless/becloudless/pkg/bcl"
	"github.com/becloudless/becloudless/pkg/cmd"
	"github.com/n0rad/go-erlog/logs"
	_ "github.com/n0rad/go-erlog/register"
)

//go:embed all:assets kube
var Embedded embed.FS
var Version = "0.0.0"

//go:generate ./dist-tools/go-jsonschema -p schema --schema-root-type global=Global ./nixos/modules/nixos/global/default.schema.json -o pkg/generated/schema/schema.go
func main() {
	bcl.BCL.Embedded = &Embedded
	bcl.BCL.Version = Version

	handleSignals()

	if err := cmd.RootCmd().Execute(); err != nil {
		logs.WithE(err).Fatal("Command failed")
	}
	os.Exit(0)
}

func handleSignals() {
	c := make(chan os.Signal, 1)
	signal.Notify(c, os.Interrupt, os.Kill)
	go func() {
		for s := range c {
			logs.WithField("signal", s).Trace("Signal received. Purging Secrets")
			memguard.Purge()
			switch s {
			case os.Interrupt:
				os.Exit(130)
			case os.Kill:
				os.Exit(143)
			default:
				os.Exit(42)
			}
		}
	}()
}
