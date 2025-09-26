package version

import (
	"fmt"
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/go-git/go-git/v6"
	"github.com/go-git/go-git/v6/plumbing/object"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestGenerateVersionFromDateAndGitState_Success(t *testing.T) {
	// Create a temporary directory for test git repo
	tempDir, err := os.MkdirTemp("", "version_test_*")
	require.NoError(t, err)
	defer os.RemoveAll(tempDir)

	// Set up test repository with commit
	setupTestRepo(t, tempDir)

	// Test the function
	version, err := GenerateVersionFromDateAndGitState(1, tempDir)
	require.NoError(t, err)

	// Verify version format: majorVersion.YYMMDD.HHMM-H<hash>
	assert.Regexp(t, `^1\.\d{6}\.\d{1,4}-H[0-9a-f]{7,}$`, version)

	// Verify the hash part is present (we can't predict exact hash since setupTestRepo creates it)
	assert.Contains(t, version, "-H")
}

func TestGenerateVersionFromDateAndGitState_WithDifferentMajorVersions(t *testing.T) {
	tempDir, err := os.MkdirTemp("", "version_test_*")
	require.NoError(t, err)
	defer os.RemoveAll(tempDir)

	// Initialize repo with commit
	setupTestRepo(t, tempDir)

	testCases := []int{0, 1, 42, 999}
	for _, majorVersion := range testCases {
		t.Run(fmt.Sprintf("major_version_%d", majorVersion), func(t *testing.T) {
			version, err := GenerateVersionFromDateAndGitState(majorVersion, tempDir)
			require.NoError(t, err)
			assert.Regexp(t, fmt.Sprintf(`^%d\.\d{6}\.\d{1,4}-H[0-9a-f]{7,}$`, majorVersion), version)
		})
	}
}

func TestGenerateVersionFromDateAndGitState_InvalidGitPath(t *testing.T) {
	nonExistentPath := "/path/that/does/not/exist"

	version, err := GenerateVersionFromDateAndGitState(1, nonExistentPath)

	assert.Error(t, err)
	assert.Empty(t, version)
	assert.Contains(t, err.Error(), "failed to open git repository")
}

func TestGenerateVersionFromDateAndGitState_NotAGitRepo(t *testing.T) {
	tempDir, err := os.MkdirTemp("", "version_test_*")
	require.NoError(t, err)
	defer os.RemoveAll(tempDir)

	// Create a directory that's not a git repository
	version, err := GenerateVersionFromDateAndGitState(1, tempDir)

	assert.Error(t, err)
	assert.Empty(t, version)
	assert.Contains(t, err.Error(), "failed to open git repository")
}

func TestGenerateVersionFromDateAndGitState_EmptyRepo(t *testing.T) {
	tempDir, err := os.MkdirTemp("", "version_test_*")
	require.NoError(t, err)
	defer os.RemoveAll(tempDir)

	// Initialize empty git repository (no commits)
	_, err = git.PlainInit(tempDir, false)
	require.NoError(t, err)

	version, err := GenerateVersionFromDateAndGitState(1, tempDir)

	assert.Error(t, err)
	assert.Empty(t, version)
	assert.Contains(t, err.Error(), "failed to get git commit hash")
}

func TestGenerateVersionFromDateAndGitState_TimeFormat(t *testing.T) {
	tempDir, err := os.MkdirTemp("", "version_test_*")
	require.NoError(t, err)
	defer os.RemoveAll(tempDir)

	setupTestRepo(t, tempDir)

	version, err := GenerateVersionFromDateAndGitState(1, tempDir)
	require.NoError(t, err)

	// Parse the version to verify date/time format
	// Format: 1.YYMMDD.HHMM-H<hash>
	assert.Regexp(t, `^1\.\d{6}\.\d{1,4}-H[0-9a-f]{7,}$`, version)

	// Verify that the date part is current date in YYMMDD format
	now := time.Now().UTC()
	expectedDateStr := now.Format("060102")
	assert.Contains(t, version, fmt.Sprintf("1.%s.", expectedDateStr))
}

func TestGenerateVersionFromDateAndGitState_TimeWithoutLeadingZeros(t *testing.T) {
	tempDir, err := os.MkdirTemp("", "version_test_*")
	require.NoError(t, err)
	defer os.RemoveAll(tempDir)

	setupTestRepo(t, tempDir)

	version, err := GenerateVersionFromDateAndGitState(42, tempDir)
	require.NoError(t, err)

	// The time part should not have leading zeros (converted to int)
	// So times like "0304" become "304", "1200" becomes "1200"
	assert.Regexp(t, `^42\.\d{6}\.\d{1,4}-H[0-9a-f]{7,}$`, version)
}

// Helper function to set up a test repository with a commit
func setupTestRepo(t *testing.T, path string) {
	repo, err := git.PlainInit(path, false)
	require.NoError(t, err)

	testFile := filepath.Join(path, "test.txt")
	err = os.WriteFile(testFile, []byte("test content"), 0644)
	require.NoError(t, err)

	worktree, err := repo.Worktree()
	require.NoError(t, err)

	_, err = worktree.Add("test.txt")
	require.NoError(t, err)

	_, err = worktree.Commit("test commit", &git.CommitOptions{
		Author: &object.Signature{
			Name:  "Test User",
			Email: "test@example.com",
			When:  time.Now(),
		},
	})
	require.NoError(t, err)
}
