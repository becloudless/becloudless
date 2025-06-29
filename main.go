package main

import (
	"embed"
	"github.com/becloudless/becloudless/pkg/bcl"
	"github.com/becloudless/becloudless/pkg/cmd"
	_ "github.com/n0rad/go-erlog/register"
)

//go:embed assets
var Assets embed.FS

func main() {
	bcl.BCL.Init(Assets)
	cmd.HandleResult(cmd.RootCmd().Execute())
}
