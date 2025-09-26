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

func TestExtractPlatformFromDockerfile_WithPlatformLabel(t *testing.T) {
	content := `FROM ubuntu:20.04
LABEL platform=linux/amd64
RUN echo "Hello World"`

	dockerfilePath := createTempDockerfile(t, content)
	platform, err := ExtractPlatformFromDockerfile(dockerfilePath)

	assert.NoError(t, err)
	assert.Equal(t, "linux/amd64", platform)
}

func TestExtractPlatformFromDockerfile_CaseInsensitivePlatformLabel(t *testing.T) {
	content := `FROM ubuntu:20.04
LABEL PLATFORM=linux/arm64
RUN echo "Hello World"`

	dockerfilePath := createTempDockerfile(t, content)
	platform, err := ExtractPlatformFromDockerfile(dockerfilePath)

	assert.NoError(t, err)
	assert.Equal(t, "linux/arm64", platform)
}

func TestExtractPlatformFromDockerfile_MixedCasePlatformLabel(t *testing.T) {
	content := `FROM ubuntu:20.04
LABEL Platform=linux/arm/v7
RUN echo "Hello World"`

	dockerfilePath := createTempDockerfile(t, content)
	platform, err := ExtractPlatformFromDockerfile(dockerfilePath)

	assert.NoError(t, err)
	assert.Equal(t, "linux/arm/v7", platform)
}

func TestExtractPlatformFromDockerfile_MultipleLabelsIncludingPlatform(t *testing.T) {
	content := `FROM ubuntu:20.04
LABEL version=1.0
LABEL platform=linux/amd64
LABEL maintainer=test@example.com
RUN echo "Hello World"`

	dockerfilePath := createTempDockerfile(t, content)
	platform, err := ExtractPlatformFromDockerfile(dockerfilePath)

	assert.NoError(t, err)
	assert.Equal(t, "linux/amd64", platform)
}

func TestExtractPlatformFromDockerfile_MultipleLabelsOnSameLineIncludingPlatform(t *testing.T) {
	content := `FROM ubuntu:20.04
LABEL version=1.0 platform=linux/s390x maintainer=test@example.com
RUN echo "Hello World"`

	dockerfilePath := createTempDockerfile(t, content)
	platform, err := ExtractPlatformFromDockerfile(dockerfilePath)

	assert.NoError(t, err)
	assert.Equal(t, "linux/s390x", platform)
}

func TestExtractPlatformFromDockerfile_WithoutPlatformLabel(t *testing.T) {
	content := `FROM ubuntu:20.04
LABEL version=1.0
LABEL maintainer=test@example.com
RUN echo "Hello World"`

	dockerfilePath := createTempDockerfile(t, content)
	platform, err := ExtractPlatformFromDockerfile(dockerfilePath)

	assert.NoError(t, err)
	assert.Empty(t, platform)
}

func TestExtractPlatformFromDockerfile_NoLabels(t *testing.T) {
	content := `FROM ubuntu:20.04
RUN echo "Hello World"`

	dockerfilePath := createTempDockerfile(t, content)
	platform, err := ExtractPlatformFromDockerfile(dockerfilePath)

	assert.NoError(t, err)
	assert.Empty(t, platform)
}

func TestExtractPlatformFromDockerfile_PlatformLabelInMultiStageBuild(t *testing.T) {
	content := `FROM ubuntu:20.04 as builder
LABEL platform=linux/amd64
RUN echo "Building"

FROM alpine:latest
COPY --from=builder /app /app`

	dockerfilePath := createTempDockerfile(t, content)
	platform, err := ExtractPlatformFromDockerfile(dockerfilePath)

	assert.NoError(t, err)
	assert.Equal(t, "linux/amd64", platform)
}

func TestExtractPlatformFromDockerfile_PlatformLabelInSecondStage(t *testing.T) {
	content := `FROM ubuntu:20.04 as builder
RUN echo "Building"

FROM alpine:latest
LABEL platform=linux/arm64
COPY --from=builder /app /app`

	dockerfilePath := createTempDockerfile(t, content)
	platform, err := ExtractPlatformFromDockerfile(dockerfilePath)

	assert.NoError(t, err)
	assert.Equal(t, "linux/arm64", platform)
}

func TestExtractPlatformFromDockerfile_PlatformLabelsInMultipleStagesFirstWins(t *testing.T) {
	content := `FROM ubuntu:20.04 as builder
LABEL platform=linux/amd64
RUN echo "Building"

FROM alpine:latest
LABEL platform=linux/arm64
COPY --from=builder /app /app`

	dockerfilePath := createTempDockerfile(t, content)
	platform, err := ExtractPlatformFromDockerfile(dockerfilePath)

	assert.NoError(t, err)
	assert.Equal(t, "linux/amd64", platform)
}

func TestExtractPlatformFromDockerfile_NonExistentFile(t *testing.T) {
	platform, err := ExtractPlatformFromDockerfile("/nonexistent/path/Dockerfile")

	assert.Error(t, err)
	assert.Empty(t, platform)
}

func TestExtractPlatformFromDockerfile_EmptyFilepath(t *testing.T) {
	platform, err := ExtractPlatformFromDockerfile("")

	assert.Error(t, err)
	assert.Empty(t, platform)
}

func TestExtractPlatformFromDockerfile_InvalidDockerfileSyntax(t *testing.T) {
	content := `INVALID INSTRUCTION
LABEL platform=linux/amd64`

	dockerfilePath := createTempDockerfile(t, content)
	platform, err := ExtractPlatformFromDockerfile(dockerfilePath)

	assert.Error(t, err)
	assert.Empty(t, platform)
}

func TestExtractPlatformFromDockerfile_EmptyFile(t *testing.T) {
	content := ""

	dockerfilePath := createTempDockerfile(t, content)
	platform, err := ExtractPlatformFromDockerfile(dockerfilePath)

	assert.Error(t, err)
	assert.Empty(t, platform)
}
