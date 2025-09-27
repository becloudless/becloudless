//go:build build

package tools

import (
	_ "github.com/client9/misspell/cmd/misspell"
	_ "github.com/fzipp/gocyclo"
	_ "github.com/go-bindata/go-bindata/v3/go-bindata"
	_ "github.com/gordonklaus/ineffassign"
	_ "golang.org/x/lint/golint"
	_ "https://github.com/omissis/go-jsonschema"
)
