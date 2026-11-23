package nixos

import (
	"testing"

	"github.com/stretchr/testify/assert"
)

func TestNixString_EscapesSpecialCharacters(t *testing.T) {
	assert.Equal(t, `"a\"b\\c\${d}"`, nixString(`a"b\c${d}`))
}
