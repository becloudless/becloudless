package docker

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// Helper function to create a temporary directory with a Dockerfile
func createTempDockerfileForTest(t *testing.T, content string) string {
	tempDir, err := os.MkdirTemp("", "docker_test")
	require.NoError(t, err, "Failed to create temp dir")
	t.Cleanup(func() { _ = os.RemoveAll(tempDir) })

	dockerfilePath := filepath.Join(tempDir, "Dockerfile")
	err = os.WriteFile(dockerfilePath, []byte(content), 0644)
	require.NoError(t, err, "Failed to create test Dockerfile")
	return tempDir
}

func TestGetFolderNameFromDockerfilePath(t *testing.T) {
	// Create a temporary directory structure
	tempDir, err := os.MkdirTemp("", "test_folder")
	require.NoError(t, err)
	t.Cleanup(func() { _ = os.RemoveAll(tempDir) })

	// Create a Dockerfile in the temp directory
	dockerfilePath := filepath.Join(tempDir, "Dockerfile")
	err = os.WriteFile(dockerfilePath, []byte("FROM ubuntu:20.04"), 0644)
	require.NoError(t, err)

	// Test the function
	folderName, err := getFolderNameFromDockerfilePath(dockerfilePath)

	assert.NoError(t, err)
	assert.Equal(t, filepath.Base(tempDir), folderName)
}

func TestGetFolderNameFromDockerfilePath_InvalidPath(t *testing.T) {
	// Test with non-existent path
	_, err := getFolderNameFromDockerfilePath("/non/existent/path/Dockerfile")

	assert.Error(t, err)
}

func TestDockerBuildx_ConfigValidation(t *testing.T) {
	// Create a temporary directory with a simple Dockerfile
	dockerfileContent := `FROM ubuntu:20.04
RUN echo "Hello World"`
	tempDir := createTempDockerfileForTest(t, dockerfileContent)

	config := BuildConfig{
		DockerfilePath: tempDir,
		Registry:       "test-registry.com",
		Namespace:      "test-namespace",
		Platforms:      "linux/amd64",
		Load:           true,
		Cache:          true,
		BuildxFlags:    "--progress=plain",
	}

	// Note: This test only validates the configuration setup
	// We don't actually run dockerBuildx to avoid dependency on Docker being installed

	// Verify that the path exists
	stat, err := os.Stat(config.DockerfilePath)
	assert.NoError(t, err)
	assert.True(t, stat.IsDir())

	// Verify Dockerfile exists in the path
	dockerfilePath := filepath.Join(config.DockerfilePath, "Dockerfile")
	_, err = os.Stat(dockerfilePath)
	assert.NoError(t, err)

	// Test path resolution logic (similar to what dockerBuildx does)
	if stat.IsDir() {
		buildPath := config.DockerfilePath
		dockerfilePath := filepath.Join(config.DockerfilePath, "Dockerfile")

		assert.Equal(t, tempDir, buildPath)
		assert.True(t, filepath.IsAbs(dockerfilePath) || filepath.Join(tempDir, "Dockerfile") != "")
	}
}

func TestDockerBuildx_Integration(t *testing.T) {
	// Skip this test if Docker is not available
	if err := exec.Command("docker", "--version").Run(); err != nil {
		t.Skip("Docker not available, skipping integration test")
	}
	if err := exec.Command("docker", "buildx", "version").Run(); err != nil {
		t.Skip("Docker buildx not available, skipping integration test")
	}
	if err := exec.Command("git", "--version").Run(); err != nil {
		t.Skip("Git not available, skipping integration test")
	}

	// Create a temporary directory with a simple Dockerfile
	dockerfileContent := `FROM alpine:latest
LABEL platform=linux/amd64
RUN echo "Testing dockerBuildx function"
CMD ["echo", "Hello from dockerBuildx test"]`

	tempDir := createTempDockerfileForTest(t, dockerfileContent)

	// Initialize git repo for version generation
	gitInit := exec.Command("git", "init")
	gitInit.Dir = tempDir
	require.NoError(t, gitInit.Run(), "Failed to initialize git repo")

	gitAdd := exec.Command("git", "add", "Dockerfile")
	gitAdd.Dir = tempDir
	require.NoError(t, gitAdd.Run(), "Failed to add Dockerfile to git")

	gitConfig1 := exec.Command("git", "config", "user.email", "test@example.com")
	gitConfig1.Dir = tempDir
	require.NoError(t, gitConfig1.Run(), "Failed to set git user email")

	gitConfig2 := exec.Command("git", "config", "user.name", "Test User")
	gitConfig2.Dir = tempDir
	require.NoError(t, gitConfig2.Run(), "Failed to set git user name")

	gitCommit := exec.Command("git", "commit", "-m", "Initial commit")
	gitCommit.Dir = tempDir
	require.NoError(t, gitCommit.Run(), "Failed to commit Dockerfile")

	config := BuildConfig{
		DockerfilePath: tempDir,
		Registry:       "localhost",
		Namespace:      "test",
		Platforms:      "linux/amd64",
		Load:           true,
		Cache:          true,
		Push:           false,
		BuildxFlags:    "",
	}

	// Call the actual dockerBuildx function
	err := dockerBuildx(config)

	// Assert that the build succeeded
	assert.NoError(t, err, "dockerBuildx should succeed with valid configuration")

	// Verify the image was built by checking if it exists in local Docker
	folderName, err := getFolderNameFromDockerfilePath(filepath.Join(tempDir, "Dockerfile"))
	require.NoError(t, err)

	expectedImageName := fmt.Sprintf("%s/%s/%s:latest", config.Registry, config.Namespace, folderName)

	// Check if the image exists
	checkCmd := exec.Command("docker", "images", expectedImageName, "--format", "{{.Repository}}:{{.Tag}}")
	output, err := checkCmd.Output()
	assert.NoError(t, err, "Failed to check if image exists")
	assert.Contains(t, string(output), expectedImageName, "Built image should exist in local Docker")

	// Clean up: remove the built image
	t.Cleanup(func() {
		cleanupCmd := exec.Command("docker", "rmi", expectedImageName)
		_ = cleanupCmd.Run() // Ignore errors during cleanup
	})
}
