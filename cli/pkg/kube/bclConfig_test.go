package kube

import (
	"testing"

	"github.com/stretchr/testify/assert"
)

func TestToEnvFromStruct(t *testing.T) {
	cfg := BclConfig{}
	cfg.Global.Name = "my-name"
	cfg.Global.Domain = "example.com"

	env := cfg.ToEnv()

	assert.Equal(t, "my-name", env["BCL_GLOBAL_NAME"])
	assert.Equal(t, "example.com", env["BCL_GLOBAL_DOMAIN"])
}
