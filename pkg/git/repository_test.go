package git

import (
	"testing"

	"github.com/stretchr/testify/assert"
)

func TestParseGitUrl_HTTP(t *testing.T) {
	host, owner, repo, err := ParseGitUrl("https://github.com/owner/repo.git")
	assert.NoError(t, err)
	assert.Equal(t, "github.com", host)
	assert.Equal(t, "owner", owner)
	assert.Equal(t, "repo", repo)
}

func TestParseGitUrl_HTTPWithoutGit(t *testing.T) {
	host, owner, repo, err := ParseGitUrl("https://git.example.com/foo/bar")
	assert.NoError(t, err)
	assert.Equal(t, "git.example.com", host)
	assert.Equal(t, "foo", owner)
	assert.Equal(t, "bar", repo)
}

func TestParseGitUrl_SSHURL(t *testing.T) {
	host, owner, repo, err := ParseGitUrl("ssh://git@gitea.example.com/org/project.git")
	assert.NoError(t, err)
	assert.Equal(t, "gitea.example.com", host)
	assert.Equal(t, "org", owner)
	assert.Equal(t, "project", repo)
}

func TestParseGitUrl_SCP(t *testing.T) {
	host, owner, repo, err := ParseGitUrl("git@github.com:owner/repo.git")
	assert.NoError(t, err)
	assert.Equal(t, "github.com", host)
	assert.Equal(t, "owner", owner)
	assert.Equal(t, "repo", repo)
}

func TestParseGitUrl_Invalid(t *testing.T) {
	_, _, _, err := ParseGitUrl("not-a-url")
	assert.Error(t, err)
}
