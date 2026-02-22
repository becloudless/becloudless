package docker

import (
	"os"

	"github.com/moby/buildkit/frontend/dockerfile/instructions"
	"github.com/moby/buildkit/frontend/dockerfile/parser"
	"github.com/n0rad/go-erlog/errs"
)

func ExtractLabelsFromDockerfile(dockerfile string) (map[string]string, error) {
	file, err := os.Open(dockerfile)
	if err != nil {
		return nil, errs.WithE(err, "failed to open Dockerfile")
	}
	defer file.Close()

	result, err := parser.Parse(file)
	if err != nil {
		return nil, errs.WithE(err, "failed to parse Dockerfile")
	}

	stages, _, err := instructions.Parse(result.AST, nil)
	if err != nil {
		return nil, errs.WithE(err, "failed to parse Dockerfile instructions")
	}

	labels := make(map[string]string)
	for _, stage := range stages {
		for _, cmd := range stage.Commands {
			if labelCmd, ok := cmd.(*instructions.LabelCommand); ok {
				for _, kv := range labelCmd.Labels {
					labels[kv.Key] = kv.Value
				}
			}
		}
	}

	return labels, nil
}
