package main

import (
	"embed"
	"github.com/becloudless/becloudless/pkg/bcl"
	"github.com/becloudless/becloudless/pkg/bcl/app/version"
	"github.com/becloudless/becloudless/pkg/cmd"
	"github.com/n0rad/go-erlog/logs"
	_ "github.com/n0rad/go-erlog/register"
	"os"
)

//go:embed all:assets
var Assets embed.FS

var Version = "0.0.0"

func main() {
	v, err := version.Parse(Version)
	if err != nil {
		logs.WithField("version", v).Fatal("Failed to parse internal bcl build version")
	}

	bcl.BCL.Version = v
	bcl.BCL.Assets = Assets

	if err := cmd.RootCmd().Execute(); err != nil {
		logs.WithE(err).Fatal("Command failed")
	}
	os.Exit(0)
}
