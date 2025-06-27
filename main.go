package main

import (
	"github.com/becloudless/becloudless/pkg/cmd"
	"os"
	"strings"

	"github.com/n0rad/go-erlog/logs"
	_ "github.com/n0rad/go-erlog/register"
)

var Version = "0.0.0"

func main() {

	if err := bcl.SetVersion(Version); err != nil {
		logs.WithE(err).Fatal("Failed to set bbc build version")
	}

	args := append([]string(nil), os.Args...)

	args, homeFolder := extractHomeFolderFromArgs(args)
	if homeFolder == "" {
		homeFolder = DefaultHomeFolder()
	}
	bcl.SetHomeFolder(homeFolder)

	if err := bcl.PrepareAssets(); err != nil {
		logs.WithE(err).Error("Cannot prepare assets for update")
	}

	cmd.HandleResult(cmd.RootCmd(args).Execute())
}

func extractHomeFolderFromArgs(args []string) ([]string, string) {
	for i, arg := range args {
		if arg == "--" {
			return args, ""
		}
		if arg == "-H" {
			args = sliceRemove(args, i)
			return sliceRemove(args, i+1), os.Args[i+1]
		}
		if strings.HasPrefix(arg, "--home=") {
			return sliceRemove(args, i), arg[7:]
		}
	}
	return args, ""
}

func sliceRemove(slice []string, s int) []string {
	return append(slice[:s], slice[s+1:]...)
}
