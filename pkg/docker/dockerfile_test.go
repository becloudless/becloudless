package docker

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// Helper function to create a temporary Dockerfile with given content
func createTempDockerfile(t *testing.T, content string) string {
	tempDir, err := os.MkdirTemp("", "dockerfile_test")
	require.NoError(t, err, "Failed to create temp dir")
	t.Cleanup(func() { _ = os.RemoveAll(tempDir) })

	dockerfilePath := filepath.Join(tempDir, "Dockerfile")
	err = os.WriteFile(dockerfilePath, []byte(content), 0644)
	require.NoError(t, err, "Failed to create test Dockerfile")
	return dockerfilePath
}

func TestExtractLabelsFromDockerfile_SinglePlatformLabel(t *testing.T) {
	content := `FROM ubuntu:20.04
LABEL platform=linux/amd64
RUN echo "Hello World"`

	dockerfilePath := createTempDockerfile(t, content)
	labels, err := ExtractLabelsFromDockerfile(dockerfilePath)

	assert.NoError(t, err)
	assert.Equal(t, map[string]string{"platform": "linux/amd64"}, labels)
}

func TestExtractLabelsFromDockerfile_MultipleLabels(t *testing.T) {
	content := `FROM ubuntu:20.04
LABEL platform=linux/amd64 version=1.0 maintainer=test@example.com
RUN echo "Hello World"`

	dockerfilePath := createTempDockerfile(t, content)
	labels, err := ExtractLabelsFromDockerfile(dockerfilePath)

	assert.NoError(t, err)
	assert.Equal(t, map[string]string{
		"platform":   "linux/amd64",
		"version":    "1.0",
		"maintainer": "test@example.com",
	}, labels)
}

func TestExtractLabelsFromDockerfile_MultipleStagesLabelsMerged(t *testing.T) {
	content := `FROM ubuntu:20.04 as builder
LABEL stage=builder platform=linux/amd64
RUN echo "Building"

FROM alpine:latest
LABEL stage=final version=2.0
COPY --from=builder /app /app`

	dockerfilePath := createTempDockerfile(t, content)
	labels, err := ExtractLabelsFromDockerfile(dockerfilePath)

	assert.NoError(t, err)
	assert.Equal(t, map[string]string{
		"stage":    "final",       // last one wins
		"platform": "linux/amd64", // from first stage
		"version":  "2.0",
	}, labels)
}

func TestExtractLabelsFromDockerfile_LabelOverride(t *testing.T) {
	content := `FROM ubuntu:20.04
LABEL version=1.0
LABEL version=2.0
RUN echo "Hello World"`

	dockerfilePath := createTempDockerfile(t, content)
	labels, err := ExtractLabelsFromDockerfile(dockerfilePath)

	assert.NoError(t, err)
	assert.Equal(t, map[string]string{"version": "2.0"}, labels)
}

func TestExtractLabelsFromDockerfile_NoLabels(t *testing.T) {
	content := `FROM ubuntu:20.04
RUN echo "Hello World"`

	dockerfilePath := createTempDockerfile(t, content)
	labels, err := ExtractLabelsFromDockerfile(dockerfilePath)

	assert.NoError(t, err)
	assert.Empty(t, labels)
}

func TestExtractLabelsFromDockerfile_NonExistentFile(t *testing.T) {
	labels, err := ExtractLabelsFromDockerfile("/nonexistent/path/Dockerfile")

	assert.Error(t, err)
	assert.Nil(t, labels)
}

func TestExtractLabelsFromDockerfile_EmptyFilepath(t *testing.T) {
	labels, err := ExtractLabelsFromDockerfile("")

	assert.Error(t, err)
	assert.Nil(t, labels)
}
