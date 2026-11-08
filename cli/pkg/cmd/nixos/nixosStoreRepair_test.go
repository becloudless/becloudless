package nixos

import (
	"strings"
	"testing"

	"github.com/stretchr/testify/assert"
)

func TestCorruptedStorePattern(t *testing.T) {
	corrupted := []string{
		"error: error parsing derivation '/nix/store/1jvaahq1wpwszzjhdn4a8sai3wm5fw8g-nixos-rebuild-ng-26.05.drv': file is empty (possible filesystem corruption)",
		"error: syntax error, unexpected end of file\n       at «github:nix-community/disko/ff8702b4de27f72b4c78573dfb89ec74e36abdf1?narHash=sha256-x»/flake.nix:1:1:",
	}
	for _, stderr := range corrupted {
		assert.True(t, corruptedStorePattern.MatchString(stderr), stderr)
	}

	healthy := []string{
		"error: Failed to fetch git repository 'ssh://git@forgejo.lmr.fr/lmr/infra.git'",
		"error: syntax error, unexpected '}'\n       at /nix/store/abc-source/nixos/flake.nix:12:3:",
		"error: syntax error, unexpected end of file\n       at /home/n0rad/infra/nixos/modules/x.nix:42:1:",
	}
	for _, stderr := range healthy {
		assert.False(t, corruptedStorePattern.MatchString(stderr), stderr)
	}
}

func TestTailBuffer(t *testing.T) {
	b := &tailBuffer{max: 10}
	_, _ = b.Write([]byte(strings.Repeat("a", 8)))
	_, _ = b.Write([]byte("bcdefg"))
	assert.Equal(t, "aaaabcdefg", b.String())
}
