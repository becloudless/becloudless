package nixos

import (
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestParseSystemNames(t *testing.T) {
	names, err := parseSystemNames(`["srv2","edge1","srv1"]`)
	require.NoError(t, err)
	assert.Equal(t, []string{"edge1", "srv1", "srv2"}, names)

	_, err = parseSystemNames(`not json`)
	assert.Error(t, err)
}

func TestCheckSystemName(t *testing.T) {
	available := []string{"edge1", "srv1"}

	assert.NoError(t, checkSystemName("srv1", available))

	err := checkSystemName("default", available)
	require.Error(t, err)
	assert.Contains(t, err.Error(), "Unknown system")
	assert.Contains(t, err.Error(), "edge1, srv1")
}
